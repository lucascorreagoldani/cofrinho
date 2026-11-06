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
import { AppError } from './shared/errors/AppError.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { usersRoutes } from './modules/users/users.routes.js';
import { checkDatabaseConnection, dbPool } from './database/postgres.js';
import { checkRedisConnection, redis } from './database/redis.js';

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

  /* 6. Tratamento Global de Erros (RFC 9457 Problem Details - Regra 2) */
  app.setErrorHandler((error: FastifyError | AppError | Error, request, reply) => {
    reply.header('Content-Type', 'application/problem+json');

    /* Erros controlados da aplicação */
    if (error instanceof AppError) {
      return reply.status(error.statusCode).send(error.toProblemDetails(request.url));
    }

    const err = error as any;

    /* Erros de validação do Zod / Fastify */
    if (err.validation) {
      const invalidParams = err.validation.map((v: any) => ({
        name: v.instancePath || v.params?.missingProperty || 'campo',
        reason: v.message || 'Valor inválido',
      }));

      return reply.status(400).send({
        type: 'https://api.cofrinho.app/errors/validation-error',
        title: 'Erro de Validação',
        status: 400,
        detail: 'Um ou mais campos da requisição não atenderam aos critérios exigidos.',
        instance: request.url,
        code: 'VALIDATION_FAILED',
        invalidParams,
      });
    }

    /* Erro 401 do JWT */
    if (err.statusCode === 401) {
      return reply.status(401).send({
        type: 'https://api.cofrinho.app/errors/unauthorized',
        title: 'Não Autorizado',
        status: 401,
        detail: 'Token de autenticação ausente, expirado ou inválido.',
        instance: request.url,
        code: 'UNAUTHORIZED',
      });
    }

    /* Erro inesperado (500) */
    request.log.error(error);
    return reply.status(500).send({
      type: 'https://api.cofrinho.app/errors/internal-server-error',
      title: 'Erro Interno do Servidor',
      status: 500,
      detail: 'Ocorreu uma falha inesperada. Nossa equipe foi notificada.',
      instance: request.url,
      code: 'INTERNAL_ERROR',
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

  return app;
}

/* 8. Inicialização do Servidor */
async function start() {
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
