import { randomBytes } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import argon2 from 'argon2';

const passwordHashOptions: import('argon2').HashOptions = {
  type: argon2.argon2id,
  memoryCost: 65_536,
  timeCost: 3,
  parallelism: 1,
};

@Injectable()
export class PasswordService {
  private readonly dummyHash = argon2.hash(randomBytes(32).toString('hex'), passwordHashOptions);

  hash(password: string): Promise<string> {
    return argon2.hash(password, passwordHashOptions);
  }

  async verify(passwordHash: string | undefined, password: string): Promise<boolean> {
    const hash = passwordHash ?? await this.dummyHash;
    try {
      const valid = await argon2.verify(hash, password);
      return Boolean(passwordHash) && valid;
    } catch {
      return false;
    }
  }
}
