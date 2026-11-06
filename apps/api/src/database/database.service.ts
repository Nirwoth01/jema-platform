import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { Pool, type PoolClient, type QueryResult, type QueryResultRow } from 'pg';
import { env } from '../config/env.js';

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly logger = new Logger(DatabaseService.name);
  private readonly pool = new Pool({
    host: env.DATABASE_HOST,
    port: env.DATABASE_PORT,
    database: env.DATABASE_NAME,
    user: env.DATABASE_USER,
    password: env.DATABASE_PASSWORD,
    ssl: env.DATABASE_SSL ? { rejectUnauthorized: true } : false,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    application_name: 'jema-api',
  });

  constructor() {
    this.pool.on('error', () => {
      this.logger.error('Connexion PostgreSQL inactive en erreur.');
    });
  }

  query<Row extends QueryResultRow = QueryResultRow>(
    sql: string,
    values: readonly unknown[] = [],
  ): Promise<QueryResult<Row>> {
    return this.pool.query<Row>(sql, [...values] as never[]);
  }

  async ping(): Promise<void> {
    await this.query<{ ready: number }>('SELECT 1 AS ready');
  }

  async transaction<Result>(work: (client: PoolClient) => Promise<Result>): Promise<Result> {
    const client = await this.pool.connect();

    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try {
        await client.query('ROLLBACK');
      } catch {
        this.logger.error('Échec de l’annulation d’une transaction PostgreSQL.');
      }
      throw error;
    } finally {
      client.release();
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}
