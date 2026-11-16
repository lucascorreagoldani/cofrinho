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
import { authenticateRequest, getAuthenticatedUserId } from '../../shared/middlewares/authenticate.js';

const accountsService = new AccountsService();

export const accountsRoutes: FastifyPluginAsyncZod = async (app) => {
  /* Hook canônico de autenticação JWT + validação de sessão no Redis/PostgreSQL */
  app.addHook('onRequest', authenticateRequest);

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
      const userId = getAuthenticatedUserId(request);
      const accounts = await accountsService.listAccounts(
        userId,
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
          401: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const account = await accountsService.createAccount(userId, request.body);
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
          401: problemDetailsSchema,
          404: problemDetailsSchema,
          409: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const updated = await accountsService.updateAccount(
        userId,
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
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      await accountsService.deleteAccount(userId, request.params.id);
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
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      const userId = getAuthenticatedUserId(request);
      const result = await accountsService.toggleAccountVisibility(userId, request.params.id);
      return reply.status(200).send(result);
    }
  );
};

