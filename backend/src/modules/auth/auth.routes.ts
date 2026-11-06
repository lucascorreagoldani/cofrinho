import { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { AuthService } from './auth.service.js';
import {
  registerBodySchema,
  loginBodySchema,
  refreshBodySchema,
  userResponseSchema,
  authSuccessResponseSchema,
  problemDetailsSchema,
} from './auth.schemas.js';
import { UnauthorizedError } from '../../shared/errors/AppError.js';

const authService = new AuthService();

export const authRoutes: FastifyPluginAsyncZod = async (app) => {
  /* 1. POST /v1/auth/register */
  app.post(
    '/register',
    {
      schema: {
        tags: ['Autenticação'],
        summary: 'Registrar novo usuário',
        description: 'Cria uma nova conta de usuário com ID numérico incremental e timestamps em epoch milissegundos.',
        body: registerBodySchema,
        response: {
          201: userResponseSchema.describe('Usuário criado com sucesso'),
          400: problemDetailsSchema.describe('Parâmetros inválidos'),
          409: problemDetailsSchema.describe('Conflito de username ou e-mail'),
        },
      },
    },
    async (request, reply) => {
      const clientIp = request.ip || '127.0.0.1';
      const user = await authService.register(request.body, clientIp);

      /* Cabeçalho Location na criação de recurso (201 Created) */
      reply.header('Location', `/v1/users/${user.id}`);
      return reply.status(201).send(user);
    }
  );

  /* 2. POST /v1/auth/login */
  app.post(
    '/login',
    {
      schema: {
        tags: ['Autenticação'],
        summary: 'Autenticar usuário e iniciar sessão',
        description: 'Valida credenciais, atualiza histórico de IP, abre sessão no Postgres e grava no Redis.',
        body: loginBodySchema,
        response: {
          200: authSuccessResponseSchema.describe('Autenticação realizada com sucesso'),
          401: problemDetailsSchema.describe('Credenciais inválidas'),
        },
      },
    },
    async (request, reply) => {
      const clientIp = request.ip || '127.0.0.1';
      const userAgent = request.headers['user-agent'] || 'Unknown';

      const result = await authService.login(request.body, clientIp, userAgent);

      /* Gera Access Token (JWT) */
      const accessToken = app.jwt.sign(
        {
          sub: String(result.user.id),
          userId: result.user.id,
          username: result.user.username,
          sessionId: result.session.id,
        },
        { expiresIn: '15m' }
      );

      /* Gera Refresh Token (JWT com tempo de expiração da sessão) */
      const refreshToken = app.jwt.sign(
        {
          sub: String(result.user.id),
          userId: result.user.id,
          sessionId: result.session.id,
          type: 'refresh',
        },
        { expiresIn: `${result.sessionDurationHours}h` }
      );

      return reply.status(200).send({
        access_token: accessToken,
        refresh_token: refreshToken,
        token_type: 'Bearer',
        expires_in: 15 * 60, /* 15 minutos em segundos */
        user: result.user,
        session: result.session,
      });
    }
  );

  /* 3. POST /v1/auth/logout */
  app.post(
    '/logout',
    {
      onRequest: [async (request) => request.jwtVerify()],
      schema: {
        tags: ['Autenticação'],
        summary: 'Encerrar sessão ativa',
        description: 'Invalida a sessão no Redis instantaneamente e registra o horário de logout no PostgreSQL.',
        response: {
          204: z.null().describe('Sessão encerrada com sucesso'),
          401: problemDetailsSchema.describe('Não autenticado'),
        },
      },
    },
    async (request, reply) => {
      const userPayload = request.user as { sessionId: string };
      if (userPayload?.sessionId) {
        await authService.logout(userPayload.sessionId);
      }
      return reply.status(204).send(null);
    }
  );

  /* 4. POST /v1/auth/refresh */
  app.post(
    '/refresh',
    {
      schema: {
        tags: ['Autenticação'],
        summary: 'Renovar Access Token via Refresh Token',
        description: 'Emite um novo access token após validar que a sessão ainda está ativa no Redis/Postgres.',
        body: refreshBodySchema,
        response: {
          200: z.object({
            access_token: z.string(),
            token_type: z.literal('Bearer'),
            expires_in: z.number().int(),
          }),
          401: problemDetailsSchema,
        },
      },
    },
    async (request, reply) => {
      try {
        const decoded = app.jwt.verify<{ sub: string; sessionId: string; type?: string }>(
          request.body.refresh_token
        );

        if (decoded.type !== 'refresh') {
          throw new UnauthorizedError('O token fornecido não é um refresh token.');
        }

        const isValid = await authService.validateSession(decoded.sessionId);
        if (!isValid) {
          throw new UnauthorizedError('Esta sessão foi revogada ou expirou.');
        }

        const newAccessToken = app.jwt.sign(
          {
            sub: decoded.sub,
            sessionId: decoded.sessionId,
          },
          { expiresIn: '15m' }
        );

        return reply.status(200).send({
          access_token: newAccessToken,
          token_type: 'Bearer',
          expires_in: 15 * 60,
        });
      } catch (err) {
        if (err instanceof UnauthorizedError) {
          throw err;
        }
        throw new UnauthorizedError('Refresh token inválido ou expirado.');
      }
    }
  );
};
