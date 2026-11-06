import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../database/database.service.js';
import type { AuthenticatedUser } from '../common/security/authenticated-user.js';
import type { UpdateProfileDto } from './dto/update-profile.dto.js';

@Injectable()
export class UsersService {
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService) {}

  async updateProfile(userId: string, dto: UpdateProfileDto): Promise<AuthenticatedUser> {
    const values: unknown[] = [userId];
    const assignments: string[] = [];

    if (dto.firstName !== undefined) {
      values.push(dto.firstName);
      assignments.push(`first_name = $${values.length}`);
    }
    if (dto.lastName !== undefined) {
      values.push(dto.lastName || null);
      assignments.push(`last_name = $${values.length}`);
    }
    if (dto.preferredLanguageCode !== undefined) {
      values.push(dto.preferredLanguageCode);
      assignments.push(`preferred_language_code = $${values.length}`);
    }
    if (assignments.length === 0) throw new BadRequestException('Fournissez au moins un champ à modifier.');

    const result = await this.database.query<{ id: string }>(
      `UPDATE users SET ${assignments.join(', ')}, updated_at = now()
       WHERE id = $1 AND deleted_at IS NULL AND account_status = 'active'
       RETURNING id`,
      values,
    );
    const updatedUser = result.rows[0];
    if (!updatedUser) throw new NotFoundException('Compte introuvable.');

    const userResult = await this.database.query<AuthenticatedUser>(
      `SELECT
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
         ) AS roles
       FROM users u
       WHERE u.id = $1 AND u.deleted_at IS NULL AND u.account_status = 'active'
       LIMIT 1`,
      [userId],
    );
    const user = userResult.rows[0];
    if (!user) throw new NotFoundException('Compte introuvable.');
    return user;
  }
}
