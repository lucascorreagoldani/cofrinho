import { z } from 'zod';

export const categoryResponseSchema = z.object({
  id: z.number().int().positive().describe('ID numérico crescente da categoria'),
  user_id: z.number().int().positive(),
  name: z.string().min(1).max(100),
  icon: z.string().min(1).max(60),
  color: z.string().regex(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, 'Cor deve estar em formato Hex (#RRGGBB)'),
  is_default: z.boolean(),
  status: z.enum(['active', 'hidden', 'deleted']),
  created_at: z.number().int(),
  updated_at: z.number().int(),
});

export const createCategoryBodySchema = z.object({
  name: z
    .string({ required_error: 'Nome da categoria é obrigatório' })
    .min(1, 'Nome não pode ser vazio')
    .max(100, 'Nome deve ter no máximo 100 caracteres')
    .trim(),
  icon: z.string().default('tag.fill'),
  color: z.string().regex(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, 'Cor inválida').default('#FF9500'),
});

export const updateCategoryBodySchema = z.object({
  name: z.string().min(1).max(100).trim().optional(),
  icon: z.string().min(1).max(60).optional(),
  color: z.string().regex(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, 'Cor inválida').optional(),
  status: z.enum(['active', 'hidden', 'deleted']).optional(),
});

export const listCategoriesQuerySchema = z.object({
  include_hidden: z.coerce.boolean().default(false),
});

