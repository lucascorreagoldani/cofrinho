import { Redis } from 'ioredis';
import { env } from '../config/env.js';

export const redis = new Redis(env.REDIS_URL, {
  maxRetriesPerRequest: 2,
  enableReadyCheck: true,
  lazyConnect: true,
  retryStrategy(times) {
    if (times > 3) {
      console.warn('⚠️ Redis não está acessível no momento. Operando sem cache...');
      return null; /* Não trava o app tentando infinitamente */
    }
    return Math.min(times * 100, 1000);
  },
});

redis.on('connect', () => {
  console.log('✅ Conexão com Redis estabelecida com sucesso.');
});

redis.on('error', (err) => {
  console.warn('⚠️ Alerta do Redis:', err.message);
});

export async function checkRedisConnection(): Promise<boolean> {
  try {
    /* Verifica se a instância já está pronta antes de forçar nova conexão */
    if (redis.status === 'ready') {
      return (await redis.ping()) === 'PONG';
    }
    if (redis.status === 'connecting' || redis.status === 'connect') {
      return true;
    }
    await redis.connect();
    return (await redis.ping()) === 'PONG';
  } catch {
    return false;
  }
}

