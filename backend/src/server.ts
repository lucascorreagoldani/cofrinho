import fastify, { FastifyError } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import jwt from '@fastify/jwt';
import swagger from '@fastify/swagger';
import swaggerUI from '@fastify/swagger-ui';
import {
  jsonSchemaTransform,
  serializerCompiler,
  validatorCompiler,
  ZodTypeProvider,
} from 'fastify-type-provider-zod';

import { env } from './config/env.js';
import {
  AppError,
  ValidationError,
  UnauthorizedError,
  InternalError,
} from './shared/errors/AppError.js';
import { ErrorAuditor } from './shared/errors/ErrorAuditor.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { usersRoutes } from './modules/users/users.routes.js';
import { categoriesRoutes } from './modules/categories/categories.routes.js';
import { accountsRoutes } from './modules/accounts/accounts.routes.js';
import { transactionsRoutes } from './modules/transactions/transactions.routes.js';
import { checkDatabaseConnection, dbPool } from './database/postgres.js';
import { checkRedisConnection, redis } from './database/redis.js';
import { initializeDatabase } from './database/init.js';

export async function buildApp() {
  const app = fastify({
    logger: {
      level: env.NODE_ENV === 'development' ? 'info' : 'warn',
    },
  }).withTypeProvider<ZodTypeProvider>();

  /* 1. Compiladores Zod */
  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  /* 2. Plugins de Segurança e Cross-Origin */
  await app.register(cors, { origin: true });
  await app.register(helmet, { contentSecurityPolicy: false }); /* Permite carregar o Swagger UI */

  /* 3. Rate Limiting Global */
  await app.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
  });

  /* 4. JWT */
  await app.register(jwt, {
    secret: env.JWT_SECRET,
  });

  /* 5. Documentação OpenAPI 3.0 / Swagger UI (Regra 6) */
  await app.register(swagger, {
    openapi: {
      info: {
        title: 'Cofrinho API',
        description: 'API REST do Cofrinho - Gestão Financeira Pessoal & Autenticação Segura',
        version: '1.0.0',
      },
      servers: [
        {
          url: `http://localhost:${env.PORT}`,
          description: 'Servidor Local de Desenvolvimento',
        },
      ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: 'http',
            scheme: 'bearer',
            bearerFormat: 'JWT',
          },
        },
      },
    },
    transform: jsonSchemaTransform,
  });

  await app.register(swaggerUI, {
    routePrefix: '/docs',
  });

  /* 6. Tratamento Global de Erros (RFC 9457 Problem Details com Auditoria de Incidentes) */
  app.setErrorHandler(async (error: FastifyError | AppError | Error, request, reply) => {
    reply.header('Content-Type', 'application/problem+json');

    const reqUser = request.user as { userId?: number; sub?: string } | undefined;
    const currentUserId = reqUser?.userId ? Number(reqUser.userId) : (reqUser?.sub ? Number(reqUser.sub) : undefined);

    /* Erros controlados da aplicação */
    if (error instanceof AppError) {
      if (error.statusCode >= 500) {
        await ErrorAuditor.log(error, {
          userId: currentUserId,
          requestUrl: request.url,
          method: request.method,
        });
      }
      return reply.status(error.statusCode).send(error.toProblemDetails(request.url));
    }

    const err = error as any;

    /* Erros de validação do Zod / Fastify */
    if (err.validation) {
      const invalidParams = err.validation.map((v: any) => ({
        name: v.instancePath || v.params?.missingProperty || 'campo',
        reason: v.message || 'Valor inválido',
      }));

      const valError = new ValidationError(
        'Um ou mais campos da requisição não atenderam aos critérios exigidos.',
        invalidParams
      );
      return reply.status(400).send(valError.toProblemDetails(request.url));
    }

    /* Erro 401 do JWT */
    if (err.statusCode === 401) {
      const unauthError = new UnauthorizedError('Token de autenticação ausente, expirado ou inválido.');
      return reply.status(401).send(unauthError.toProblemDetails(request.url));
    }

    /* Erro inesperado (500) com persistência de auditoria */
    request.log.error(error);
    const incidentId = await ErrorAuditor.log(error, {
      userId: currentUserId,
      requestUrl: request.url,
      method: request.method,
    });

    const internalErr = new InternalError('Ocorreu uma falha inesperada. Protocolo de suporte gerado.');
    return reply.status(500).send({
      ...internalErr.toProblemDetails(request.url),
      incidentId,
    });
  });

  /* Rota de Health Check */
  app.get('/health', async () => {
    const [dbOk, redisOk] = await Promise.all([
      checkDatabaseConnection(),
      checkRedisConnection(),
    ]);

    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      services: {
        postgres: dbOk ? 'healthy' : 'unreachable',
        redis: redisOk ? 'healthy' : 'unreachable',
      },
    };
  });

  /* 7. Registro de Rotas Versionadas (/v1 - Regra 5) */
  await app.register(authRoutes, { prefix: '/v1/auth' });
  await app.register(usersRoutes, { prefix: '/v1/users' });
  await app.register(categoriesRoutes, { prefix: '/v1/categories' });
  await app.register(accountsRoutes, { prefix: '/v1/accounts' });
  await app.register(transactionsRoutes, { prefix: '/v1/transactions' });

  return app;
}

/* 8. Inicialização do Servidor */
async function start() {
  try {
    /* Garante idempotência de esquemas no PostgreSQL */
    await initializeDatabase();
  } catch (err) {
    console.error('Aviso: Falha ao sincronizar esquema no startup:', (err as Error).message);
  }

  const app = await buildApp();

  try {
    await app.listen({ port: env.PORT, host: env.HOST });
    console.log(`🚀 Servidor Cofrinho API rodando em http://${env.HOST}:${env.PORT}`);
    console.log(`📚 Documentação Swagger UI disponível em http://${env.HOST}:${env.PORT}/docs`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }

  /* Finalização graciosa */
  const signals: NodeJS.Signals[] = ['SIGINT', 'SIGTERM'];
  for (const signal of signals) {
    process.on(signal, async () => {
      console.log(`\n🛑 Sinal ${signal} recebido. Encerrando servidor e conexões...`);
      await app.close();
      await dbPool.end();
      redis.disconnect();
      process.exit(0);
    });
  }
}

/* Executa se chamado diretamente */
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/.*\//, ''))) {
  start();
}
