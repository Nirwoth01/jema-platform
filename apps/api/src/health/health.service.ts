import { Inject, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DatabaseService } from '../database/database.service.js';

@Injectable()
export class HealthService {
  constructor(@Inject(DatabaseService) private readonly database: DatabaseService) {}

  live() {
    return {
      status: 'ok' as const,
      service: 'jema-api',
      timestamp: new Date().toISOString(),
    };
  }

  async ready() {
    try {
      await this.database.ping();
      return {
        status: 'ok' as const,
        service: 'jema-api',
        dependencies: { postgres: 'ok' as const },
        timestamp: new Date().toISOString(),
      };
    } catch {
      throw new ServiceUnavailableException('La base de données est temporairement indisponible.');
    }
  }
}
