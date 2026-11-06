import { z } from 'zod';

export const transactionStatusSchema = z.enum(['active', 'hidden', 'deleted']);
export const transactionTypeSchema = z.enum(['expense', 'income']);

export const transactionCategoryRelationSchema = z.object({
  id: z.number().int().positive(),
  name: z.string(),
  icon: z.string(),
  color: z.string(),
});

export const transactionAccountRelationSchema = z.object({
  id: z.number().int().positive(),
  name: z.string(),
  type: z.string(),
  icon: z.string(),
  color: z.string(),
});

export const transactionResponseSchema = z.object({
  id: z.number().int().positive().describe('ID numérico crescente do gasto'),
  user_id: z.number().int().positive(),
  category_id: z.number().int().positive(),
  category: transactionCategoryRelationSchema.optional(),
  account_id: z.number().int().positive(),
  account: transactionAccountRelationSchema.optional(),
  type: transactionTypeSchema,
  amount: z.number().positive().describe('Valor em reais (ex: 120.50)'),
  description: z.string(),
  date: z.number().int().describe('Timestamp numérico em epoch ms'),
  has_time: z.boolean(),
  status: transactionStatusSchema,
  is_installment: z.boolean(),
  installment_number: z.number().int().nullable().optional(),
  total_installments: z.number().int().nullable().optional(),
  installment_group_id: z.string().uuid().nullable().optional(),
  created_at: z.number().int(),
  updated_at: z.number().int(),
});

export const createTransactionBodySchema = z.object({
  description: z
    .string({ required_error: 'Descrição é obrigatória' })
    .min(1, 'A descrição deve ter no mínimo 1 caractere')
    .max(255, 'A descrição deve ter no máximo 255 caracteres')
    .trim(),
  amount: z.number({ required_error: 'Valor é obrigatório' }).positive('O valor deve ser maior que zero'),
  date: z.number({ required_error: 'Data é obrigatória' }).int().describe('Data em epoch milissegundos'),
  has_time: z.boolean().default(false),
  category_id: z.number({ required_error: 'Categoria é obrigatória' }).int().positive(),
  account_id: z.number({ required_error: 'Conta é obrigatória' }).int().positive(),
  type: transactionTypeSchema.default('expense'),
  installments: z
    .object({
      enabled: z.boolean().default(false),
      count: z.number().int().min(2, 'Parcelamento mínimo de 2 parcelas').max(72, 'Parcelamento máximo de 72 parcelas').default(2),
    })
    .optional(),
});

export const updateTransactionBodySchema = z.object({
  description: z.string().min(1).max(255).trim().optional(),
  amount: z.number().positive().optional(),
  date: z.number().int().optional(),
  has_time: z.boolean().optional(),
  category_id: z.number().int().positive().optional(),
  account_id: z.number().int().positive().optional(),
  status: transactionStatusSchema.optional(),
});

export const listTransactionsQuerySchema = z.object({
  month: z.coerce.number().int().min(1).max(12).optional(),
  year: z.coerce.number().int().min(2000).max(2100).optional(),
  status: transactionStatusSchema.default('active'),
  category_id: z.coerce.number().int().positive().optional(),
  account_id: z.coerce.number().int().positive().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

export const deleteTransactionQuerySchema = z.object({
  cascade: z.enum(['single', 'all_future']).default('single'),
});

export const suggestionItemSchema = z.object({
  description: z.string(),
  suggested_category_id: z.number().int().positive().nullable(),
  suggested_account_id: z.number().int().positive().nullable(),
  count: z.number().int(),
});
