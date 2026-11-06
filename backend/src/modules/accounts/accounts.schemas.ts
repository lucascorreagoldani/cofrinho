import { z } from 'zod';

export const accountTypeSchema = z.enum([
  'credit_card',
  'bank_account',
  'wallet',
  'pix',
  'cash',
]);

export const accountResponseSchema = z.object({
  id: z.number().int().positive().describe('ID numérico crescente da conta'),
  user_id: z.number().int().positive(),
  name: z.string().min(1).max(100),
  type: accountTypeSchema,
  icon: z.string().min(1).max(60),
  color: z.string().regex(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, 'Cor deve estar em formato Hex (#RRGGBB)'),
  allows_installments: z.boolean(),
  closing_day: z.number().int().min(1).max(31).nullable().optional(),
  due_day: z.number().int().min(1).max(31).nullable().optional(),
  status: z.enum(['active', 'hidden', 'deleted']),
  created_at: z.number().int(),
  updated_at: z.number().int(),
});

export const createAccountBodySchema = z
  .object({
    name: z
      .string({ required_error: 'Nome da conta é obrigatório' })
      .min(1, 'Nome não pode ser vazio')
      .max(100, 'Nome deve ter no máximo 100 caracteres')
      .trim(),
    type: accountTypeSchema.default('bank_account'),
    icon: z.string().default('creditcard.fill'),
    color: z.string().regex(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, 'Cor inválida').default('#007AFF'),
    allows_installments: z.boolean().default(false),
    closing_day: z.number().int().min(1).max(31).optional(),
    due_day: z.number().int().min(1).max(31).optional(),
  })
  .refine(
    (data) => {
      /* Se permite parcelas e tipo for cartão, dia de fechamento e vencimento são recomendados */
      if (data.allows_installments && (data.closing_day === undefined || data.due_day === undefined)) {
        return false;
      }
      return true;
    },
    {
      message: 'Contas que aceitam parcelamento exigem informar o dia de fechamento e o dia de vencimento da fatura.',
      path: ['closing_day'],
    }
  );

export const updateAccountBodySchema = z.object({
  name: z.string().min(1).max(100).trim().optional(),
  type: accountTypeSchema.optional(),
  icon: z.string().min(1).max(60).optional(),
  color: z.string().regex(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, 'Cor inválida').optional(),
  allows_installments: z.boolean().optional(),
  closing_day: z.number().int().min(1).max(31).nullable().optional(),
  due_day: z.number().int().min(1).max(31).nullable().optional(),
  status: z.enum(['active', 'hidden', 'deleted']).optional(),
});

export const listAccountsQuerySchema = z.object({
  include_hidden: z.coerce.boolean().default(false),
});

