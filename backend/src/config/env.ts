import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(3000),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().default('postgresql://cofrinho:cofrinho_secret@localhost:5432/cofrinho_db'),
  REDIS_URL: z.string().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET deve ter no mínimo 32 caracteres'),
  JWT_EXPIRES_IN: z.string().default('15m'),
  REFRESH_TOKEN_EXPIRES_IN: z.string().default('7d'),
});

const _env = envSchema.safeParse(process.env);

if (!_env.success) {
  console.error('❌ Variáveis de ambiente inválidas:', _env.error.format());
  throw new Error('Configuração de ambiente inválida.');
}

export const env = _env.data;

