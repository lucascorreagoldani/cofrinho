import { z } from 'zod';

export const userProfileSchema = z.object({
  id: z.string().uuid(),
  username: z.string(),
  email: z.string().email(),
  first_ip: z.string(),
  last_ip: z.string(),
  first_login: z.string().nullable().optional(),
  last_login: z.string().nullable().optional(),
  registered_at: z.string(),
});

export const userPreferencesSchema = z.object({
  user_id: z.string().uuid(),
  fast_login: z.boolean(),
  verification: z.boolean(),
  updated_at: z.string(),
});

export const updatePreferencesBodySchema = z.object({
  fast_login: z.boolean().optional(),
  verification: z.boolean().optional(),
}).refine(data => data.fast_login !== undefined || data.verification !== undefined, {
  message: 'Pelo menos uma preferência deve ser informada para atualização',
});

/* Regra 3: Paginação não pode ser tardia (limits e cursores) */
export const sessionListQuerySchema = z.object({
  limit: z.coerce.number().min(1).max(100).default(20),
  cursor: z.string().uuid().optional(),
});

export const sessionItemSchema = z.object({
  id: z.string().uuid(),
  login_time: z.string(),
  logout_time: z.string().nullable().optional(),
  duration: z.number().nullable().optional(),
  status: z.string(),
  ip: z.string(),
  user_agent: z.string().nullable().optional(),
  is_current: z.boolean(),
});

export const sessionListResponseSchema = z.object({
  data: z.array(sessionItemSchema),
  pagination: z.object({
    limit: z.number(),
    next_cursor: z.string().uuid().nullable(),
    has_more: z.boolean(),
  }),
});

