import { z } from 'zod';

export const userProfileSchema = z.object({
  id: z.number().int().positive().describe('ID numérico crescente (1, 2, 3...)'),
  username: z.string(),
  email: z.string().email(),
  first_ip: z.string(),
  last_ip: z.string(),
  first_login: z.number().int().nullable().optional().describe('Timestamp em epoch milissegundos do primeiro login'),
  last_login: z.number().int().nullable().optional().describe('Timestamp em epoch milissegundos do último login'),
  registered_at: z.number().int().describe('Timestamp em epoch milissegundos do cadastro'),
});

export const userPreferencesSchema = z.object({
  user_id: z.number().int().positive().describe('ID numérico do usuário'),
  fast_login: z.boolean(),
  verification: z.boolean(),
  updated_at: z.number().int().describe('Timestamp de atualização em epoch milissegundos'),
});

export const updatePreferencesBodySchema = z.object({
  fast_login: z.boolean().optional(),
  verification: z.boolean().optional(),
}).refine(data => data.fast_login !== undefined || data.verification !== undefined, {
  message: 'Pelo menos uma preferência deve ser informada para atualização',
});

/* Paginação com limites e cursores */
export const sessionListQuerySchema = z.object({
  limit: z.coerce.number().min(1).max(100).default(20),
  cursor: z.string().uuid().optional(),
});

export const sessionItemSchema = z.object({
  id: z.string().uuid(),
  login_time: z.number().int().describe('Timestamp de login em epoch milissegundos'),
  logout_time: z.number().int().nullable().optional().describe('Timestamp de logout em epoch milissegundos'),
  duration: z.number().int().nullable().optional().describe('Duração da sessão em milissegundos'),
  status: z.string(),
  ip: z.string(),
  user_agent: z.string().nullable().optional(),
  is_current: z.boolean(),
});

export const sessionListResponseSchema = z.object({
  data: z.array(sessionItemSchema),
  pagination: z.object({
    limit: z.number().int(),
    next_cursor: z.string().uuid().nullable(),
    has_more: z.boolean(),
  }),
});
