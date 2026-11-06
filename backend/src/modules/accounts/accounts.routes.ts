import { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { AccountsService } from './accounts.service.js';
import {
  accountResponseSchema,
  createAccountBodySchema,
  updateAccountBodySchema,
  listAccountsQuerySchema,
} from './accounts.schemas.js';
import { problemDetailsSchema } from '../auth/auth.schemas.js';

const accountsService = new AccountsService();

export const accountsRoutes: FastifyPluginAsyncZod = async (app) => {
  /* Hook de Autenticação JWT */
  app.addHook('onRequest', async (request, reply) => {
    try {
      await request.jwtVerify();
    } catch (err) {
      return reply.status(401).send({
        type: 'https://cofrinho.app/errors/unauthorized',
        title: 'Não Autorizado',
        status: 401,
        detail: 'Token de autenticação ausente ou expirado.',
        code: 'AUTH_001',
        incidentId: 'incident_jwt_required',
        timestamp: Date.now(),
      });
    }
  });

  /* 1. GET /v1/accounts - Listar contas */
  app.get(
    '',
    {
      schema: {
        tags: ['Contas'],
        summary: 'Listar contas e cartões do usuário',
        querystring: listAccountsQuerySchema,
        response: {
          200: z.array(accountResponseSchema),
          401: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      const accounts = await accountsService.listAccounts(
        userPayload.userId,
        request.query.include_hidden
      );
      return reply.status(200).send(accounts);
    }
  );

  /* 2. POST /v1/accounts - Criar conta */
  app.post(
    '',
    {
      schema: {
        tags: ['Contas'],
        summary: 'Criar nova conta ou cartão',
        body: createAccountBodySchema,
        response: {
          201: accountResponseSchema,
          400: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      const account = await accountsService.createAccount(userPayload.userId, request.body);
      return reply.status(201).send(account);
    }
  );

  /* 3. PUT /v1/accounts/:id - Atualizar conta */
  app.put(
    '/:id',
    {
      schema: {
        tags: ['Contas'],
        summary: 'Atualizar configurações de conta ou cartão',
        params: z.object({ id: z.coerce.number().int().positive() }),
        body: updateAccountBodySchema,
        response: {
          200: accountResponseSchema,
          404: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      const updated = await accountsService.updateAccount(
        userPayload.userId,
        request.params.id,
        request.body
      );
      return reply.status(200).send(updated);
    }
  );

  /* 4. DELETE /v1/accounts/:id - Excluir conta (soft delete) */
  app.delete(
    '/:id',
    {
      schema: {
        tags: ['Contas'],
        summary: 'Excluir conta (soft delete)',
        params: z.object({ id: z.coerce.number().int().positive() }),
        response: {
          204: z.null(),
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      await accountsService.deleteAccount(userPayload.userId, request.params.id);
      return reply.status(204).send(null);
    }
  );

  /* 5. PATCH /v1/accounts/:id/visibility - Ocultar ou Desocultar */
  app.patch(
    '/:id/visibility',
    {
      schema: {
        tags: ['Contas'],
        summary: 'Alternar visibilidade (ativo / oculto)',
        params: z.object({ id: z.coerce.number().int().positive() }),
        response: {
          200: accountResponseSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { userId: number };
      const result = await accountsService.toggleAccountVisibility(userPayload.userId, request.params.id);
      return reply.status(200).send(result);
    }
  );
};

