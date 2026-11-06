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
  AUTH_TOKEN_PEPPER: z.string()
    .min(43, 'doit contenir au moins 32 octets aléatoires en base64url')
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'doit utiliser le format base64url ou hexadécimal')
    .refine((value) => !value.startsWith('REMPLACER_'), 'doit être remplacée par une vraie clé aléatoire'),
  AUTH_EXPOSE_DEV_CODES: z.enum(['true', 'false']).default('false').transform((value) => value === 'true'),
  AUTH_SESSION_TTL_HOURS: z.coerce.number().int().min(1).max(720).default(720),
  AUTH_CODE_TTL_MINUTES: z.coerce.number().int().min(5).max(30).default(15),
  AUTH_RESET_TTL_MINUTES: z.coerce.number().int().min(5).max(60).default(30),
}).superRefine((configuration, context) => {
  if (
    configuration.AUTH_EXPOSE_DEV_CODES &&
    (configuration.NODE_ENV !== 'development' || !['127.0.0.1', '::1', 'localhost'].includes(configuration.API_HOST))
  ) {
    context.addIssue({
      code: 'custom',
      path: ['AUTH_EXPOSE_DEV_CODES'],
      message: 'est réservé au développement local sur loopback',
    });
  }
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
