---
name: cofrinho-redis
description: Guia canônico de padrões de engenharia e modelagem do Redis no Cofrinho (namespaces, cache de sessões <1ms, timestamps numéricos, TTLs, serialização, resiliência e circuit breaker).
---

# 🔴 Cofrinho Redis — Guia Canônico de Engenharia & Cache

Este guia estabelece os padrões arquiteturais, convenções de chaves, estratégias de resiliência e modelos de dados para o uso do **Redis 7+** no ecossistema do **Cofrinho** (Fastify, TypeScript, ioredis).

---

## 1. Princípios Fundamentais

1. **Namespace Estrito (`cofrinho:*`)**:
   - Toda chave no Redis DEVE ser prefixada com `cofrinho:` para evitar colisão com instâncias compartilhadas ou outros microserviços.
2. **Timestamps Numéricos (`epoch ms`)**:
   - NUNCA armazene datas como strings ISO-8601 (`"2026-11-06T..."`). Utilize exclusivamente inteiros numéricos em milissegundos (`Date.now()`).
3. **Resiliência Não-Bloqueante (Circuit Breaker)**:
   - A indisponibilidade do Redis NUNCA deve derrubar ou travar a API HTTP. Operações de leitura caem em fallback gracioso para o PostgreSQL.
4. **TTL Mandatório para Dados Voláteis**:
   - Toda sessão, token temporário ou rate limit DEVE possuir expiração explícita (`EX` em segundos ou `PX` em milissegundos).
5. **Porta Mapeada em Produção (`6380:6379`)**:
   - Na VPS com KowaMC, o container `cofrinho-redis` mapeia a porta host **`6380`** para o container **`6379`**, evitando conflito com a porta padrão `6379` do KowaMC.

---

## 2. Topologia de Chaves & Padrões de Nomes

| Padrão de Chave | Tipo Redis | TTL Típico | Finalidade | Exemplo de Chave |
| :--- | :--- | :--- | :--- | :--- |
| `cofrinho:session:<sessionId>` | String (JSON) | 24h ou 7d | Validação instantânea de sessão (<1ms) | `cofrinho:session:7c3de013-fd6e-4aea-bdc0-ca38b74de90a` |
| `cofrinho:user:<userId>:cache` | Hash / JSON | 1h | Cache de perfil de usuário e preferências | `cofrinho:user:1:cache` |
| `cofrinho:ratelimit:<ip>:<route>` | Integer | 60s | Contador de rate limiting por janela | `cofrinho:ratelimit:198.89.99.42:login` |
| `cofrinho:token:refresh:<tokenHash>` | String | 7d | Validação de blacklist e rotação de refresh token | `cofrinho:token:refresh:a1b2c3d4...` |

---

## 3. Modelo de Dados de Sessão (JSON com Timestamp Numérico)

### Estrutura do Payload:
```json
{
  "userId": 1,
  "username": "lucas",
  "sessionId": "7c3de013-fd6e-4aea-bdc0-ca38b74de90a",
  "ip": "198.89.99.42",
  "fastLogin": true,
  "expiresAt": 1794574000000,
  "loginTime": 1793969200000
}
```

### Exemplo Canônico de Escrita (com TTL):
```typescript
import { redis } from '../database/redis.js';

export async function storeSession(
  sessionId: string,
  userId: number,
  username: string,
  clientIp: string,
  fastLogin: boolean
): Promise<void> {
  const now = Date.now();
  const durationHours = fastLogin ? 24 * 7 : 24;
  const ttlSeconds = durationHours * 3600;
  const expiresAt = now + ttlSeconds * 1000;

  const payload = JSON.stringify({
    userId,
    username,
    sessionId,
    ip: clientIp,
    fastLogin,
    expiresAt,
    loginTime: now,
  });

  /* Gravação atômica com expiração */
  await redis.set(`cofrinho:session:${sessionId}`, payload, 'EX', ttlSeconds);
}
```

### Exemplo Canônico de Leitura & Validação com Fallback:
```typescript
import { redis } from '../database/redis.js';
import { dbPool } from '../database/postgres.js';

export async function validateSession(sessionId: string): Promise<boolean> {
  /* 1. Tenta validar no Redis (<1ms) */
  try {
    const raw = await redis.get(`cofrinho:session:${sessionId}`);
    if (raw) {
      const data = JSON.parse(raw);
      if (data.expiresAt && data.expiresAt > Date.now()) {
        return true;
      }
      /* Se expirou, limpa chave no Redis */
      await redis.del(`cofrinho:session:${sessionId}`);
      return false;
    }
  } catch (err) {
    console.warn('⚠️ Falha ao ler do Redis. Executando fallback para PostgreSQL...');
  }

  /* 2. Fallback resiliente no PostgreSQL */
  const result = await dbPool.query(
    `SELECT id FROM users_sessions WHERE id = $1 AND status = 'active' AND expires_at > $2`,
    [sessionId, Date.now()]
  );

  return result.rows.length > 0;
}
```

### Invalidação Atômica (Logout):
```typescript
export async function revokeSession(sessionId: string): Promise<void> {
  /* Exclusão da chave invalida instantaneamente a sessão */
  await redis.del(`cofrinho:session:${sessionId}`);
}
```

---

## 4. Configuração Resiliente do Cliente `ioredis`

O cliente Redis do Cofrinho deve usar **lazy connection** e **estratégia de retentativas finitas** para evitar travamentos de requisições:

```typescript
import { Redis } from 'ioredis';
import { env } from '../config/env.js';

export const redis = new Redis(env.REDIS_URL, {
  maxRetriesPerRequest: 2,
  enableReadyCheck: true,
  lazyConnect: true,
  retryStrategy(times) {
    if (times > 3) {
      console.warn('⚠️ Redis inacessível após 3 tentativas. Operando em modo degradado sem cache.');
      return null; /* Cancela loop infinito */
    }
    return Math.min(times * 100, 1000);
  },
});
```

---

## 5. Anti-Patterns (O que NUNCA fazer)

- ❌ **NUNCA use `KEYS *`**: Bloqueia a thread principal do Redis e causa latência extrema. Use `SCAN` se precisar iterar.
- ❌ **NUNCA salve chaves sem namespace**: Chaves soltas como `session:123` geram colisão e poluição no cluster. Use sempre `cofrinho:session:123`.
- ❌ **NUNCA salve timestamps como string ISO**: Datas como `"2026-11-06T12:00:00Z"` consomem mais memória e exigem parsing complexo. Use sempre `Date.now()`.
- ❌ **NUNCA dê crash na aplicação se o Redis falhar**: Redis é cache e aceleração; a fonte da verdade relacional é o PostgreSQL. Trate exceções com `try/catch` e degrade com elegância.
