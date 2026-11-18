import { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { env } from '../../config/env.js';
import { checkDatabaseConnection } from '../../database/postgres.js';
import { checkRedisConnection, redis } from '../../database/redis.js';
import {
  RecordStatus,
  TransactionFilterStatus,
  TransactionType,
  AccountType,
  DeleteCascadeMode,
  SessionStatus,
  ErrorLogStatus,
} from '../../shared/constants/enums.js';
import {
  CANONICAL_CATEGORIES,
  CANONICAL_ACCOUNTS,
} from '../../shared/constants/defaults.js';

/**
 * Rotas da API Pública de Utilitários (/v1/public).
 * Não requerem JWT nem sessão ativa, servindo telemetria de status,
 * sincronização de relógio e catálogo canônico de domínios para clientes.
 */
export const publicRoutes: FastifyPluginAsyncZod = async (app) => {
  /* 1. GET /v1/public/status - Status público do sistema e serviços */
  app.get(
    '/status',
    {
      schema: {
        tags: ['Público'],
        summary: 'Obter status público da API, versão e saúde dos serviços',
        response: {
          200: z.object({
            status: z.enum(['online', 'degraded']),
            version: z.string(),
            environment: z.string(),
            server_time_ms: z.number().int(),
            services: z.object({
              postgres: z.enum(['healthy', 'unreachable']),
              redis: z.enum(['healthy', 'unreachable']),
            }),
          }),
        },
      },
    },
    async () => {
      const [dbOk, redisOk] = await Promise.all([
        checkDatabaseConnection(),
        checkRedisConnection(),
      ]);

      return {
        status: dbOk && redisOk ? ('online' as const) : ('degraded' as const),
        version: '1.0.0',
        environment: env.NODE_ENV,
        server_time_ms: Date.now(),
        services: {
          postgres: dbOk ? ('healthy' as const) : ('unreachable' as const),
          redis: redisOk ? ('healthy' as const) : ('unreachable' as const),
        },
      };
    }
  );

  /* 2. GET /v1/public/enums - Enums canônicos e catálogos padrão */
  app.get(
    '/enums',
    {
      schema: {
        tags: ['Público'],
        summary: 'Obter enums canônicos de domínio, padrões de personalização e cache Redis',
        response: {
          200: z.object({
            enums: z.object({
              record_status: z.array(z.string()),
              transaction_filter_status: z.array(z.string()),
              transaction_type: z.array(z.string()),
              account_type: z.array(z.string()),
              delete_cascade_mode: z.array(z.string()),
              session_status: z.array(z.string()),
              error_log_status: z.array(z.string()),
            }),
            defaults: z.object({
              categories: z.array(
                z.object({
                  name: z.string(),
                  icon: z.string(),
                  color: z.string(),
                })
              ),
              accounts: z.array(
                z.object({
                  name: z.string(),
                  type: z.string(),
                  icon: z.string(),
                  color: z.string(),
                  allows_installments: z.boolean(),
                  closing_day: z.number().int().optional(),
                  due_day: z.number().int().optional(),
                })
              ),
            }),
            personalization: z.object({
              category_icons: z.array(z.string()),
              account_icons: z.array(z.string()),
              colors: z.array(z.string()),
            }),
          }),
        },
      },
    },
    async () => {
      const cacheKey = 'cofrinho:public:enums';
      try {
        const cached = await redis.get(cacheKey);
        if (cached) {
          return JSON.parse(cached);
        }
      } catch {
        /* Fallback resiliente se o Redis oscilar */
      }

      const payload = {
        enums: {
          record_status: Object.values(RecordStatus),
          transaction_filter_status: Object.values(TransactionFilterStatus),
          transaction_type: Object.values(TransactionType),
          account_type: Object.values(AccountType),
          delete_cascade_mode: Object.values(DeleteCascadeMode),
          session_status: Object.values(SessionStatus),
          error_log_status: Object.values(ErrorLogStatus),
        },
        defaults: {
          categories: [...CANONICAL_CATEGORIES],
          accounts: CANONICAL_ACCOUNTS.map((acc) => ({
            ...acc,
            type: acc.type as string,
          })),
        },
        personalization: {
          category_icons: [
            'cart.fill',
            'fork.knife',
            'car.fill',
            'house.fill',
            'gamecontroller.fill',
            'heart.fill',
            'graduationcap.fill',
            'airplane',
            'gift.fill',
            'bag.fill',
            'bolt.fill',
            'tag.fill',
          ],
          account_icons: [
            'creditcard.fill',
            'building.columns.fill',
            'wallet.pass.fill',
            'bolt.horizontal.fill',
            'banknote.fill',
          ],
          colors: [
            '#FF9500',
            '#34C759',
            '#007AFF',
            '#AF52DE',
            '#FF3B30',
            '#5856D6',
            '#FF2D55',
            '#00C7BE',
          ],
        },
      };

      try {
        await redis.set(cacheKey, JSON.stringify(payload), 'EX', 3600);
      } catch {
        /* Redis fallback */
      }

      return payload;
    }
  );

  /* 3. GET /v1/public/time - Utilitário leve para sincronização de timestamp */
  app.get(
    '/time',
    {
      schema: {
        tags: ['Público'],
        summary: 'Obter timestamp oficial do servidor em epoch milissegundos',
        response: {
          200: z.object({
            timestamp: z.number().int(),
          }),
        },
      },
    },
    async () => {
      return {
        timestamp: Date.now(),
      };
    }
  );
};
