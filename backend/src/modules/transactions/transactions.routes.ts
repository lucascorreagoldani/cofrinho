import { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { TransactionsService } from './transactions.service.js';
import {
  transactionResponseSchema,
  createTransactionBodySchema,
  updateTransactionBodySchema,
  listTransactionsQuerySchema,
  deleteTransactionQuerySchema,
  suggestionItemSchema,
} from './transactions.schemas.js';
import { problemDetailsSchema } from '../auth/auth.schemas.js';
import { authenticateRequest, getAuthenticatedUserId } from '../../shared/middlewares/authenticate.js';

const transactionsService = new TransactionsService();

export const transactionsRoutes: FastifyPluginAsyncZod = async (app) => {
  /* Hook canônico de autenticação JWT + validação de sessão no Redis/PostgreSQL */
  app.addHook('onRequest', authenticateRequest);

  /* 1. GET /v1/transactions - Listar gastos */
  app.get(
    '',
    {
      schema: {
        tags: ['Gastos'],
        summary: 'Listar gastos e transações do usuário',
        querystring: listTransactionsQuerySchema,
        response: {
          200: z.array(transactionResponseSchema),
          401: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const transactions = await transactionsService.listTransactions(
        userId,
        request.query
      );
      return reply.status(200).send(transactions);
    }
  );

  /* 2. GET /v1/transactions/suggestions - Autocomplete de gastos frequentes */
  app.get(
    '/suggestions',
    {
      schema: {
        tags: ['Gastos'],
        summary: 'Sugestões inteligentes de gastos frequentes para autocomplete rápido',
        querystring: z.object({
          q: z.string().optional().default(''),
        }),
        response: {
          200: z.array(suggestionItemSchema),
          401: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const suggestions = await transactionsService.getSuggestions(
        userId,
        request.query.q
      );
      return reply.status(200).send(suggestions);
    }
  );

  /* 3. POST /v1/transactions - Cadastrar novo gasto (à vista ou parcelado) */
  app.post(
    '',
    {
      schema: {
        tags: ['Gastos'],
        summary: 'Cadastrar novo gasto (suporta compras à vista ou parceladas no cartão)',
        body: createTransactionBodySchema,
        response: {
          201: transactionResponseSchema,
          400: problemDetailsSchema,
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const transaction = await transactionsService.createTransaction(
        userId,
        request.body
      );
      return reply.status(201).send(transaction);
    }
  );

  /* 4. PUT /v1/transactions/:id - Atualizar gasto */
  app.put(
    '/:id',
    {
      schema: {
        tags: ['Gastos'],
        summary: 'Editar gasto existente',
        params: z.object({ id: z.coerce.number().int().positive() }),
        body: updateTransactionBodySchema,
        response: {
          200: transactionResponseSchema,
          400: problemDetailsSchema,
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const updated = await transactionsService.updateTransaction(
        userId,
        request.params.id,
        request.body
      );
      return reply.status(200).send(updated);
    }
  );

  /* 5. DELETE /v1/transactions/:id - Excluir gasto (soft delete com suporte a cascata de parcelas futuras) */
  app.delete(
    '/:id',
    {
      schema: {
        tags: ['Gastos'],
        summary: 'Remover gasto (soft delete com suporte a cascata de parcelas)',
        params: z.object({ id: z.coerce.number().int().positive() }),
        querystring: deleteTransactionQuerySchema,
        response: {
          200: z.object({ success: z.boolean() }),
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const result = await transactionsService.deleteTransaction(
        userId,
        request.params.id,
        request.query.cascade
      );
      return reply.status(200).send(result);
    }
  );

  /* 6. PATCH /v1/transactions/:id/visibility - Ocultar ou reativar gasto */
  app.patch(
    '/:id/visibility',
    {
      schema: {
        tags: ['Gastos'],
        summary: 'Alternar visibilidade do gasto (ativo <-> ocultado)',
        params: z.object({ id: z.coerce.number().int().positive() }),
        response: {
          200: transactionResponseSchema,
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const toggled = await transactionsService.toggleTransactionVisibility(
        userId,
        request.params.id
      );
      return reply.status(200).send(toggled);
    }
  );
};

