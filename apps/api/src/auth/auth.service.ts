import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { isEmail } from 'class-validator';
import type { PoolClient } from 'pg';
import { DatabaseService } from '../database/database.service.js';
import type { AuthenticatedUser } from '../common/security/authenticated-user.js';
import { env } from '../config/env.js';
import type {
  ForgotPasswordDto,
  LoginDto,
  RegisterDto,
  ResetPasswordDto,
  VerifyCodeDto,
} from './dto/auth.dto.js';
import { PasswordService } from './password.service.js';

type Channel = 'email' | 'sms';
type Purpose = 'signup' | 'password_reset';

interface NormalizedIdentifier {
  email: string | null;
  phone: string | null;
  destination: string;
  channel: Channel;
}

interface CredentialRow {
  id: string;
  password_hash: string;
  account_status: AuthenticatedUser['accountStatus'];
  deleted_at: Date | null;
}

interface PublicUserRow {
  id: string;
  firstName: string;
  lastName: string | null;
  email: string | null;
  phoneE164: string | null;
  preferredLanguageCode: 'fr' | 'en';
  accountStatus: AuthenticatedUser['accountStatus'];
  emailVerifiedAt: Date | null;
  phoneVerifiedAt: Date | null;
  createdAt: Date;
  roles: string[];
}

interface PendingChallengeRow {
  id: string;
  user_id: string;
  token_hash: string;
  attempts: number;
  channel: Channel;
}

const publicUserColumns = `
  u.id,
  u.first_name AS "firstName",
  u.last_name AS "lastName",
  u.email,
  u.phone_e164 AS "phoneE164",
  u.preferred_language_code AS "preferredLanguageCode",
  u.account_status AS "accountStatus",
  u.email_verified_at AS "emailVerifiedAt",
  u.phone_verified_at AS "phoneVerifiedAt",
  u.created_at AS "createdAt",
  COALESCE(
    (SELECT array_agg(r.code ORDER BY r.code)
     FROM user_roles ur JOIN roles r ON r.id = ur.role_id
     WHERE ur.user_id = u.id),
    ARRAY[]::text[]
  ) AS roles`;

const genericRecoveryMessage = 'Si un compte correspondant existe, les instructions de récupération ont été préparées.';

@Injectable()
export class AuthService {
  constructor(
    @Inject(DatabaseService) private readonly database: DatabaseService,
    @Inject(PasswordService) private readonly passwords: PasswordService,
  ) {}

  async register(dto: RegisterDto): Promise<{ user: AuthenticatedUser; developmentCode?: string }> {
    this.assertCodeDeliveryAvailable();
    const email = dto.email?.trim().toLowerCase() ?? null;
    const phone = dto.phoneE164?.trim() ?? null;
    if (Boolean(email) === Boolean(phone)) {
      throw new BadRequestException('Fournissez un seul identifiant vérifiable : un e-mail ou un numéro de téléphone.');
    }

    const channel: Channel = dto.verificationChannel ?? (phone ? 'sms' : 'email');
    const destination = channel === 'sms' ? phone : email;
    if (!destination) {
      throw new BadRequestException(channel === 'sms'
        ? 'Un numéro de téléphone est requis pour la vérification SMS.'
        : 'Une adresse e-mail est requise pour la vérification par e-mail.');
    }

    const passwordHash = await this.passwords.hash(dto.password);
    const code = this.newVerificationCode();

    try {
      const userId = await this.database.transaction(async (client) => {
        const userResult = await client.query<{ id: string }>(
          `INSERT INTO users (
             first_name, last_name, email, phone_e164, password_hash,
             preferred_language_code, account_status
           ) VALUES ($1, $2, $3, $4, $5, $6, 'pending')
           RETURNING id`,
          [dto.firstName, dto.lastName?.trim() || null, email, phone, passwordHash, dto.preferredLanguageCode ?? 'fr'],
        );
        const createdUser = userResult.rows[0];
        if (!createdUser) throw new Error('La création du compte n’a retourné aucun identifiant.');

        const roleResult = await client.query(
          `INSERT INTO user_roles (user_id, role_id)
           SELECT $1, id FROM roles WHERE code = 'buyer'
           ON CONFLICT (user_id, role_id) DO NOTHING`,
          [createdUser.id],
        );
        if (roleResult.rowCount !== 1) throw new Error('Le rôle acheteur initial est indisponible.');

        const challengeStored = await this.storeVerificationChallenge(client, {
          userId: createdUser.id,
          channel,
          destination,
          code,
        });
        if (!challengeStored) throw new Error('Le compte en attente de vérification est indisponible.');
        return createdUser.id;
      });

      const user = await this.getPublicUser(userId);
      if (!user) throw new Error('Le compte créé est introuvable.');
      return {
        user,
        ...(env.AUTH_EXPOSE_DEV_CODES ? { developmentCode: code } : {}),
      };
    } catch (error) {
      if (this.isUniqueViolation(error)) {
        throw new ConflictException('Un compte utilise déjà cet e-mail ou ce numéro.');
      }
      throw error;
    }
  }

  async login(dto: LoginDto, userAgent: string | undefined): Promise<{ user: AuthenticatedUser; sessionToken: string }> {
    const identifier = this.normalizeIdentifier(dto.identifier);
    const result = await this.database.query<CredentialRow>(
      `SELECT id, password_hash, account_status, deleted_at
       FROM users
       WHERE ($1::text IS NOT NULL AND lower(email) = $1 AND email_verified_at IS NOT NULL)
          OR ($2::text IS NOT NULL AND phone_e164 = $2 AND phone_verified_at IS NOT NULL)
       LIMIT 1`,
      [identifier.email, identifier.phone],
    );
    const account = result.rows[0];
    const passwordMatches = await this.passwords.verify(account?.password_hash, dto.password);

    if (!account || !passwordMatches || account.deleted_at || account.account_status !== 'active') {
      throw new UnauthorizedException('Identifiants invalides ou compte non vérifié.');
    }

    const sessionToken = this.newSessionToken();
    await this.database.transaction(async (client) => {
      const updated = await client.query(
        `UPDATE users SET last_login_at = now(), updated_at = now()
         WHERE id = $1 AND account_status = 'active' AND deleted_at IS NULL`,
        [account.id],
      );
      if (updated.rowCount !== 1) throw new UnauthorizedException('Identifiants invalides ou compte non vérifié.');
      await this.insertSession(client, account.id, sessionToken, userAgent);
    });

    const user = await this.getPublicUser(account.id);
    if (!user) throw new UnauthorizedException('Session invalide.');
    return { user, sessionToken };
  }

  async verifySignupCode(
    dto: VerifyCodeDto,
    userAgent: string | undefined,
  ): Promise<{ user: AuthenticatedUser; sessionToken: string }> {
    const identifier = this.normalizeIdentifier(dto.identifier);
    const expectedHash = this.tokenDigest('signup', identifier.destination, dto.code);
    const sessionToken = this.newSessionToken();

    const userId = await this.database.transaction(async (client) => {
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [identifier.destination]);
      const challengeResult = await client.query<PendingChallengeRow>(
        `SELECT id, user_id, token_hash, attempts, channel
         FROM verification_challenges
         WHERE destination = $1 AND purpose = 'signup'
           AND consumed_at IS NULL AND expires_at > now()
         ORDER BY created_at DESC
         LIMIT 1
         FOR UPDATE`,
        [identifier.destination],
      );
      const challenge = challengeResult.rows[0];
      if (!challenge) return null;

      const attemptUpdate = await client.query(
        `UPDATE verification_challenges
         SET attempts = attempts + 1,
             consumed_at = CASE WHEN attempts + 1 >= 5 THEN now() ELSE consumed_at END
         WHERE id = $1`,
        [challenge.id],
      );
      if (attemptUpdate.rowCount !== 1 || challenge.attempts >= 5) return null;
      if (!this.equalHashes(challenge.token_hash, expectedHash)) return null;

      const verified = await client.query(
        `UPDATE users
         SET account_status = 'active',
             email_verified_at = CASE WHEN $2 = 'email' THEN now() ELSE email_verified_at END,
             phone_verified_at = CASE WHEN $2 = 'sms' THEN now() ELSE phone_verified_at END,
             updated_at = now()
         WHERE id = $1 AND account_status = 'pending' AND deleted_at IS NULL`,
        [challenge.user_id, challenge.channel],
      );
      if (verified.rowCount !== 1) return null;

      await client.query(
        'UPDATE verification_challenges SET consumed_at = now() WHERE id = $1 AND consumed_at IS NULL',
        [challenge.id],
      );
      await this.insertSession(client, challenge.user_id, sessionToken, userAgent);
      return challenge.user_id;
    });

    if (!userId) throw new UnauthorizedException('Code invalide ou expiré.');
    const user = await this.getPublicUser(userId);
    if (!user) throw new UnauthorizedException('Session invalide.');
    return { user, sessionToken };
  }

  async resendSignupCode(identifierValue: string): Promise<{ message: string; developmentCode?: string }> {
    this.assertCodeDeliveryAvailable();
    const identifier = this.normalizeIdentifier(identifierValue);
    const result = await this.database.query<{ id: string; account_status: string }>(
      `SELECT id, account_status FROM users
       WHERE ($1::text IS NOT NULL AND lower(email) = $1)
          OR ($2::text IS NOT NULL AND phone_e164 = $2)
       LIMIT 1`,
      [identifier.email, identifier.phone],
    );
    const account = result.rows[0];
    if (!account || account.account_status !== 'pending') {
      return { message: 'Si un compte en attente correspond, un nouveau code a été préparé.' };
    }

    const code = this.newVerificationCode();
    const challengeStored = await this.database.transaction((client) => this.storeVerificationChallenge(client, {
      userId: account.id,
      channel: identifier.channel,
      destination: identifier.destination,
      code,
    }));
    if (!challengeStored) {
      return { message: 'Si un compte en attente correspond, un nouveau code a été préparé.' };
    }

    return {
      message: 'Si un compte en attente correspond, un nouveau code a été préparé.',
      ...(env.AUTH_EXPOSE_DEV_CODES ? { developmentCode: code } : {}),
    };
  }

  async requestPasswordReset(dto: ForgotPasswordDto): Promise<{ message: string; developmentToken?: string }> {
    this.assertCodeDeliveryAvailable();
    const identifier = this.normalizeIdentifier(dto.identifier);
    const result = await this.database.query<{ id: string; account_status: string }>(
      `SELECT id, account_status FROM users
       WHERE (
         ($1::text IS NOT NULL AND lower(email) = $1 AND email_verified_at IS NOT NULL)
         OR ($2::text IS NOT NULL AND phone_e164 = $2 AND phone_verified_at IS NOT NULL)
       ) AND deleted_at IS NULL
       LIMIT 1`,
      [identifier.email, identifier.phone],
    );
    const account = result.rows[0];
    if (!account || account.account_status !== 'active') return { message: genericRecoveryMessage };

    const token = randomBytes(32).toString('base64url');
    const tokenHash = this.tokenDigest('password_reset', identifier.destination, token);
    const issued = await this.database.transaction(async (client) => {
      const lockedAccount = await client.query<{ id: string }>(
        `SELECT id FROM users
         WHERE id = $1 AND account_status = 'active' AND deleted_at IS NULL
         FOR UPDATE`,
        [account.id],
      );
      if (lockedAccount.rowCount !== 1) return false;
      await client.query(
        `UPDATE password_reset_tokens SET consumed_at = now()
         WHERE user_id = $1 AND consumed_at IS NULL`,
        [account.id],
      );
      await client.query(
        `INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, now() + ($3::integer * interval '1 minute'))`,
        [account.id, tokenHash, env.AUTH_RESET_TTL_MINUTES],
      );
      return true;
    });
    if (!issued) return { message: genericRecoveryMessage };

    return {
      message: genericRecoveryMessage,
      ...(env.AUTH_EXPOSE_DEV_CODES ? { developmentToken: token } : {}),
    };
  }

  async resetPassword(dto: ResetPasswordDto): Promise<{ passwordChanged: true }> {
    const identifier = this.normalizeIdentifier(dto.identifier);
    const tokenHash = this.tokenDigest('password_reset', identifier.destination, dto.token);

    const candidateResult = await this.database.query<{ id: string; user_id: string }>(
      `SELECT prt.id, prt.user_id
       FROM password_reset_tokens prt
       JOIN users u ON u.id = prt.user_id
       WHERE prt.token_hash = $1
         AND (($2::text IS NOT NULL AND lower(u.email) = $2 AND u.email_verified_at IS NOT NULL)
           OR ($3::text IS NOT NULL AND u.phone_e164 = $3 AND u.phone_verified_at IS NOT NULL))
         AND prt.consumed_at IS NULL AND prt.expires_at > now()
         AND u.account_status = 'active' AND u.deleted_at IS NULL
       LIMIT 1`,
      [tokenHash, identifier.email, identifier.phone],
    );
    if (!candidateResult.rows[0]) throw new UnauthorizedException('Lien de récupération invalide ou expiré.');

    const newPasswordHash = await this.passwords.hash(dto.newPassword);

    const updated = await this.database.transaction(async (client) => {
      const lockedUser = await client.query<{ id: string }>(
        `SELECT id FROM users
         WHERE id = $1 AND account_status = 'active' AND deleted_at IS NULL
           AND (($2::text IS NOT NULL AND lower(email) = $2 AND email_verified_at IS NOT NULL)
             OR ($3::text IS NOT NULL AND phone_e164 = $3 AND phone_verified_at IS NOT NULL))
         FOR UPDATE`,
        [candidateResult.rows[0]!.user_id, identifier.email, identifier.phone],
      );
      if (lockedUser.rowCount !== 1) return false;

      const tokenResult = await client.query<{ id: string }>(
        `SELECT id FROM password_reset_tokens
         WHERE user_id = $1 AND token_hash = $2
           AND consumed_at IS NULL AND expires_at > now()
         LIMIT 1 FOR UPDATE`,
        [candidateResult.rows[0]!.user_id, tokenHash],
      );
      const resetToken = tokenResult.rows[0];
      if (!resetToken) return false;

      const passwordUpdate = await client.query(
        `UPDATE users SET password_hash = $2, updated_at = now()
         WHERE id = $1 AND deleted_at IS NULL`,
        [candidateResult.rows[0]!.user_id, newPasswordHash],
      );
      if (passwordUpdate.rowCount !== 1) return false;

      await client.query(
        `UPDATE password_reset_tokens SET consumed_at = now()
         WHERE user_id = $1 AND consumed_at IS NULL`,
        [candidateResult.rows[0]!.user_id],
      );
      await client.query(
        'UPDATE user_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [candidateResult.rows[0]!.user_id],
      );
      return true;
    });

    if (!updated) throw new UnauthorizedException('Lien de récupération invalide ou expiré.');
    return { passwordChanged: true };
  }

  async logout(sessionToken: string | undefined): Promise<void> {
    if (!sessionToken || sessionToken.length < 32 || sessionToken.length > 128) return;
    await this.database.query(
      `UPDATE user_sessions SET revoked_at = now()
       WHERE token_hash = $1 AND revoked_at IS NULL`,
      [this.hashSessionToken(sessionToken)],
    );
  }

  async findAuthenticatedSession(sessionToken: string): Promise<AuthenticatedUser | null> {
    if (sessionToken.length < 32 || sessionToken.length > 128) return null;
    const result = await this.database.query<PublicUserRow>(
      `SELECT ${publicUserColumns}
       FROM user_sessions s
       JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > now()
         AND u.account_status = 'active' AND u.deleted_at IS NULL
       LIMIT 1`,
      [this.hashSessionToken(sessionToken)],
    );
    return result.rows[0] ? this.mapPublicUser(result.rows[0]) : null;
  }

  async getPublicUser(userId: string): Promise<AuthenticatedUser | null> {
    const result = await this.database.query<PublicUserRow>(
      `SELECT ${publicUserColumns}
       FROM users u
       WHERE u.id = $1 AND u.deleted_at IS NULL
       LIMIT 1`,
      [userId],
    );
    return result.rows[0] ? this.mapPublicUser(result.rows[0]) : null;
  }

  private async storeVerificationChallenge(
    client: PoolClient,
    input: { userId: string; channel: Channel; destination: string; code: string },
  ): Promise<boolean> {
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [input.destination]);
    const pendingAccount = await client.query<{ id: string }>(
      `SELECT id FROM users
       WHERE id = $1 AND account_status = 'pending' AND deleted_at IS NULL
       FOR UPDATE`,
      [input.userId],
    );
    if (pendingAccount.rowCount !== 1) return false;

    await client.query(
      `UPDATE verification_challenges SET consumed_at = now()
       WHERE destination = $1 AND purpose = 'signup' AND consumed_at IS NULL`,
      [input.destination],
    );
    await client.query(
      `INSERT INTO verification_challenges
         (user_id, channel, purpose, destination, token_hash, expires_at)
       VALUES ($1, $2, 'signup', $3, $4, now() + ($5::integer * interval '1 minute'))`,
      [
        input.userId,
        input.channel,
        input.destination,
        this.tokenDigest('signup', input.destination, input.code),
        env.AUTH_CODE_TTL_MINUTES,
      ],
    );
    return true;
  }

  private async insertSession(
    client: PoolClient,
    userId: string,
    sessionToken: string,
    userAgent: string | undefined,
  ): Promise<void> {
    const expiresAt = new Date(Date.now() + env.AUTH_SESSION_TTL_HOURS * 60 * 60 * 1_000);
    await client.query(
      `INSERT INTO user_sessions (user_id, token_hash, user_agent, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [userId, this.hashSessionToken(sessionToken), userAgent?.slice(0, 500) ?? null, expiresAt],
    );
  }

  private normalizeIdentifier(value: string): NormalizedIdentifier {
    const normalized = value.trim();
    if (normalized.includes('@')) {
      const email = normalized.toLowerCase();
      if (!isEmail(email)) throw new BadRequestException('Identifiant e-mail invalide.');
      return { email, phone: null, destination: email, channel: 'email' };
    }

    if (!/^\+[1-9]\d{7,14}$/.test(normalized)) {
      throw new BadRequestException('L’identifiant doit être un e-mail ou un numéro au format +243… .');
    }
    return { email: null, phone: normalized, destination: normalized, channel: 'sms' };
  }

  private newVerificationCode(): string {
    return randomInt(0, 1_000_000).toString().padStart(6, '0');
  }

  private newSessionToken(): string {
    return randomBytes(32).toString('base64url');
  }

  private hashSessionToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private tokenDigest(purpose: Purpose, destination: string, token: string): string {
    return createHmac('sha256', env.AUTH_TOKEN_PEPPER)
      .update(`${purpose}\0${destination}\0${token}`)
      .digest('hex');
  }

  private equalHashes(stored: string, candidate: string): boolean {
    const storedBuffer = Buffer.from(stored, 'hex');
    const candidateBuffer = Buffer.from(candidate, 'hex');
    return storedBuffer.length === candidateBuffer.length && timingSafeEqual(storedBuffer, candidateBuffer);
  }

  private assertCodeDeliveryAvailable(): void {
    if (!env.AUTH_EXPOSE_DEV_CODES) {
      throw new ServiceUnavailableException('Le canal d’envoi e-mail/SMS doit être configuré avant d’activer cette opération.');
    }
  }

  private isUniqueViolation(error: unknown): boolean {
    return typeof error === 'object' && error !== null && 'code' in error && error.code === '23505';
  }

  private mapPublicUser(row: PublicUserRow): AuthenticatedUser {
    return {
      ...row,
      emailVerifiedAt: row.emailVerifiedAt?.toISOString() ?? null,
      phoneVerifiedAt: row.phoneVerifiedAt?.toISOString() ?? null,
      createdAt: row.createdAt.toISOString(),
    };
  }
}
