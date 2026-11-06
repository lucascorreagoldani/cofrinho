import { z } from 'zod';

export const registerBodySchema = z.object({
  username: z
    .string({ required_error: 'Nome de usuário é obrigatório' })
    .min(3, 'O nome de usuário deve ter no mínimo 3 caracteres')
    .max(50, 'O nome de usuário deve ter no máximo 50 caracteres')
    .regex(/^[a-zA-Z0-9_.-]+$/, 'Nome de usuário pode conter apenas letras, números, sublinhado, ponto e traço'),
  email: z
    .string({ required_error: 'E-mail é obrigatório' })
    .email('Formato de e-mail inválido'),
  password: z
    .string({ required_error: 'Senha é obrigatória' })
    .min(8, 'A senha deve conter no mínimo 8 caracteres')
    .regex(/[A-Z]/, 'A senha deve conter pelo menos uma letra maiúscula')
    .regex(/[0-9]/, 'A senha deve conter pelo menos um número'),
});

export const loginBodySchema = z.object({
  login: z.string({ required_error: 'Usuário ou e-mail é obrigatório' }).min(1),
  password: z.string({ required_error: 'Senha é obrigatória' }).min(1),
  fast_login: z.boolean().default(true),
});

export const refreshBodySchema = z.object({
  refresh_token: z.string({ required_error: 'Refresh token é obrigatório' }),
});

export const userResponseSchema = z.object({
  id: z.string().uuid(),
  username: z.string(),
  email: z.string().email(),
  first_ip: z.string(),
  last_ip: z.string(),
  first_login: z.string().nullable().optional(),
  last_login: z.string().nullable().optional(),
  registered_at: z.string(),
});

export const authSuccessResponseSchema = z.object({
  access_token: z.string(),
  refresh_token: z.string(),
  token_type: z.literal('Bearer'),
  expires_in: z.number(), /* Segundos */
  user: userResponseSchema,
  session: z.object({
    id: z.string().uuid(),
    status: z.string(),
    expires_at: z.string(),
  }),
});

export const problemDetailsSchema = z.object({
  type: z.string(),
  title: z.string(),
  status: z.number(),
  detail: z.string(),
  instance: z.string().optional(),
  code: z.string(),
  invalidParams: z.array(z.object({ name: z.string(), reason: z.string() })).optional(),
});
