import { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { UsersService } from './users.service.js';
import {
  userProfileSchema,
  userPreferencesSchema,
  updatePreferencesBodySchema,
  sessionListQuerySchema,
  sessionListResponseSchema,
} from './users.schemas.js';
import { problemDetailsSchema } from '../auth/auth.schemas.js';

const usersService = new UsersService();

export const usersRoutes: FastifyPluginAsyncZod = async (app) => {
  /* Protege todas as rotas com autenticação JWT */
  app.addHook('onRequest', async (request) => {
    await request.jwtVerify();
  });

  /* 1. GET /v1/users/me */
  app.get(
    '/me',
    {
      schema: {
        tags: ['Usuários'],
        summary: 'Obter perfil do usuário autenticado',
        response: {
          200: userProfileSchema,
          401: problemDetailsSchema,
          404: problemDetailsSchema,
        },
      },
    },
    async (request) => {
      const { sub: userId } = request.user as { sub: string };
      return usersService.getProfile(userId);
    }
  );

  /* 2. GET /v1/users/me/preferences */
  app.get(
    '/me/preferences',
    {
      schema: {
        tags: ['Usuários'],
        summary: 'Obter preferências do usuário (Fast Login e Verificação Biométrica)',
        response: {
          200: userPreferencesSchema,
          401: problemDetailsSchema,
        },
      },
    },
    async (request) => {
      const { sub: userId } = request.user as { sub: string };
      return usersService.getPreferences(userId);
    }
  );

  /* 3. PATCH /v1/users/me/preferences */
  app.patch(
    '/me/preferences',
    {
      schema: {
        tags: ['Usuários'],
        summary: 'Atualizar preferências parciais (fast_login, verification)',
        body: updatePreferencesBodySchema,
        response: {
          200: userPreferencesSchema,
          400: problemDetailsSchema,
          401: problemDetailsSchema,
        },
      },
    },
    async (request) => {
      const { sub: userId } = request.user as { sub: string };
      return usersService.updatePreferences(userId, request.body);
    }
  );

  /* 4. GET /v1/users/me/sessions */
  app.get(
    '/me/sessions',
    {
      schema: {
        tags: ['Usuários'],
        summary: 'Listar histórico de sessões com paginação',
        querystring: sessionListQuerySchema,
        response: {
          200: sessionListResponseSchema,
          401: problemDetailsSchema,
        },
      },
    },
    async (request) => {
      const { sub: userId, sessionId } = request.user as { sub: string; sessionId: string };
      const { limit, cursor } = request.query;
      return usersService.listSessions(userId, sessionId, limit, cursor);
    }
  );
};

