---
name: cofrinho-postgres
description: Guia canônico de modelagem e persistência no PostgreSQL para o Cofrinho (IDs crescentes BIGSERIAL 1, 2, 3..., timestamps numéricos BIGINT epoch ms, pool pooling, transações seguras e auditoria de erros).
---

# 🐘 Cofrinho PostgreSQL — Guia Canônico de Modelagem & Persistência

Este guia estabelece os padrões arquiteturais, regras de modelagem relacional, gerenciamento de conexões e auditoria para o **PostgreSQL 16+** no ecossistema do **Cofrinho** (Fastify, TypeScript, `pg`).

---

## 1. Princípios Inegociáveis

1. **IDs Numéricos Crescentes (`BIGSERIAL` 1, 2, 3...)**:
   - Entidades principais (usuários, transações, categorias, orçamentos, logs) utilizam chaves primárias numéricas auto-incrementais (`BIGSERIAL PRIMARY KEY`), permitindo relacionamentos compactos, alta performance de indexação B-Tree e compatibilidade universal.
2. **Timestamps Numéricos em Milissegundos (`BIGINT` Epoch ms)**:
   - Toda coluna temporal (`created_at`, `updated_at`, `registered_at`, `expires_at`, `timestamp`) DEVE ser do tipo `BIGINT`, armazenando a quantidade de milissegundos desde a era Unix (`(extract(epoch from now()) * 1000)::bigint` no SQL e `Date.now()` no TypeScript).
3. **Parametrização Obrigatória (`$1, $2...`)**:
   - PROIBIDA qualquer interpolação direta de strings em comandos SQL. Todas as queries DEVEM utilizar placeholders `$1, $2, ...` para proteção contra SQL Injection.
4. **Gerenciamento Seguro de Conexões (`client.release()` em `finally`)**:
   - Ao obter um cliente do pool (`await dbPool.connect()`), a devolução no bloco `finally` é mandatória para impedir vazamento de conexões no Hikari / pg.Pool.
5. **Auditoria Centralizada de Erros (`log_errors`)**:
   - Exceções críticas e erros 500 são persistidos na tabela `log_errors` com `incident_id` UUID, código de erro e rastreamento de stack.
6. **Porta Mapeada em Produção (`5433:5432`)**:
   - Na VPS com KowaMC, o container `cofrinho-postgres` expõe a porta host **`5433`** para a porta interna **`5432`**, evitando colisão com a instância PostgreSQL existente do KowaMC (porta 5432).

---

## 2. Esquema DDL Canônico

```sql
-- 1. Tabela USERS
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    first_ip VARCHAR(45) NOT NULL,
    last_ip VARCHAR(45) NOT NULL,
    ip_history JSONB NOT NULL DEFAULT '[]'::jsonb,
    first_login BIGINT,
    last_login BIGINT,
    last_session UUID,
    password_hash VARCHAR(255) NOT NULL,
    registered_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    updated_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- 2. Tabela USERS_SESSIONS
CREATE TABLE IF NOT EXISTS users_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    login_time BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    logout_time BIGINT,
    duration BIGINT, -- Duração em milissegundos
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'revoked')),
    ip VARCHAR(45) NOT NULL,
    user_agent VARCHAR(255),
    expires_at BIGINT NOT NULL -- Expiração em epoch milissegundos
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON users_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON users_sessions(status);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON users_sessions(expires_at);

-- 3. Tabela USERS_PREFERENCES
CREATE TABLE IF NOT EXISTS users_preferences (
    user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    fast_login BOOLEAN NOT NULL DEFAULT true,
    verification BOOLEAN NOT NULL DEFAULT false,
    updated_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint
);

-- 4. Tabela LOG_ERRORS
CREATE TABLE IF NOT EXISTS log_errors (
    id BIGSERIAL PRIMARY KEY,
    incident_id VARCHAR(36) NOT NULL UNIQUE,
    user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    message TEXT NOT NULL,
    code VARCHAR(50) NOT NULL DEFAULT 'INTERNAL_ERROR',
    status_code INTEGER NOT NULL DEFAULT 500,
    error_trace TEXT,
    context_data JSONB,
    timestamp BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RESOLVED', 'IGNORED'))
);
```

---

## 3. Padrão de Transações com `BEGIN` / `COMMIT` / `ROLLBACK`

Toda mutação que envolve mais de uma tabela DEVE executar dentro de uma transação atômica:

```typescript
import { dbPool } from '../database/postgres.js';

export async function createUserWithPreferences(userData: UserInput, clientIp: string) {
  const client = await dbPool.connect();

  try {
    await client.query('BEGIN');

    const nowTimestamp = Date.now();

    /* 1. Inserção na tabela principal users */
    const userResult = await client.query(
      `INSERT INTO users (username, email, password_hash, first_ip, last_ip, ip_history, registered_at, updated_at)
       VALUES ($1, $2, $3, $4, $4, $5::jsonb, $6, $6)
       RETURNING id, username, email, registered_at`,
      [userData.username, userData.email, userData.passwordHash, clientIp, JSON.stringify([clientIp]), nowTimestamp]
    );

    const newUser = userResult.rows[0];
    const numericUserId = Number(newUser.id); /* Converte BIGSERIAL string/int para number */

    /* 2. Inserção na tabela filha users_preferences */
    await client.query(
      `INSERT INTO users_preferences (user_id, fast_login, verification, updated_at)
       VALUES ($1, true, false, $2)`,
      [numericUserId, nowTimestamp]
    );

    await client.query('COMMIT');

    return {
      id: numericUserId,
      username: newUser.username,
      email: newUser.email,
      registered_at: Number(newUser.registered_at),
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release(); /* NUNCA esqueça o release no pool */
  }
}
```

---

## 4. Auditoria de Falhas e Erros

Quando ocorrer uma falha não controlada (500) ou erro de banco de dados, utilize a classe `ErrorAuditor`:

```typescript
import { ErrorAuditor } from '../shared/errors/ErrorAuditor.js';

/* O ErrorAuditor grava assincronamente na tabela log_errors */
const incidentId = await ErrorAuditor.log(error, {
  userId: currentUserId,
  requestUrl: request.url,
  method: request.method,
});

/* Retorne o incidentId para o usuário/cliente com status 500 */
```

---

## 5. Conversão e Tipagem de BigInt em TypeScript

O driver `pg` retorna colunas `BIGINT` como strings JavaScript para evitar estouro de precisão acima de $2^{53} - 1$. No Cofrinho:
- IDs e timestamps cabem confortavelmente dentro de `Number.MAX_SAFE_INTEGER` ($9 \times 10^{15}$, suficiente para IDs e timestamps até o ano 285420).
- Converta explicitamente com `Number(row.id)` e `Number(row.registered_at)` antes de retornar à API ou validar com Zod.

