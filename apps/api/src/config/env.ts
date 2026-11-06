import 'dotenv/config';
import { z } from 'zod';

const environmentSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  API_HOST: z.string().trim().min(1).default('127.0.0.1'),
  API_PORT: z.coerce.number().int().min(1).max(65_535).default(3_001),
  DATABASE_HOST: z.string().trim().min(1).default('127.0.0.1'),
  DATABASE_PORT: z.coerce.number().int().min(1).max(65_535).default(5_432),
  DATABASE_NAME: z.string().trim().min(1).default('jema_dev'),
  DATABASE_USER: z.string().trim().min(1).default('postgres'),
  DATABASE_PASSWORD: z.string().min(1, 'est requis'),
  DATABASE_SSL: z.enum(['true', 'false']).default('false').transform((value) => value === 'true'),
  CORS_ORIGINS: z.string().default('http://localhost:3000,http://127.0.0.1:3000'),
});

const result = environmentSchema.safeParse(process.env);

if (!result.success) {
  const invalidVariables = [...new Set(result.error.issues.map((issue) => String(issue.path[0])))];
  throw new Error(`Configuration invalide. Vérifiez les variables : ${invalidVariables.join(', ')}.`);
}

export const env = result.data;

export const corsOrigins = new Set(
  env.CORS_ORIGINS.split(',').map((origin) => origin.trim()).filter(Boolean),
);
