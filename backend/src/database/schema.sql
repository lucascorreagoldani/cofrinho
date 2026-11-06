-- =============================================================================
-- COFRINHO DATABASE SCHEMA (PostgreSQL)
-- =============================================================================

-- 1. Tabela USERS (ID Crescente 1, 2, 3... e Timestamps em Epoch Milissegundos)
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

-- 2. Tabela USERS_SESSIONS (Sessões ativas com Expiração em Timestamp)
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

-- FK circular de users.last_session para users_sessions.id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_last_session'
    ) THEN
        ALTER TABLE users 
        ADD CONSTRAINT fk_users_last_session 
        FOREIGN KEY (last_session) REFERENCES users_sessions(id) ON DELETE SET NULL;
    END IF;
END $$;

-- 3. Tabela USERS_PREFERENCES (Relação 1:1 estrita)
CREATE TABLE IF NOT EXISTS users_preferences (
    user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    fast_login BOOLEAN NOT NULL DEFAULT true,      -- "Manter Logado"
    verification BOOLEAN NOT NULL DEFAULT false,   -- "Face ID e Touch ID"
    updated_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint
);

-- 4. Tabela LOG_ERRORS (Auditoria Centralizada de Incidentes e B.O)
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

CREATE INDEX IF NOT EXISTS idx_log_errors_incident ON log_errors(incident_id);
CREATE INDEX IF NOT EXISTS idx_log_errors_timestamp ON log_errors(timestamp);
CREATE INDEX IF NOT EXISTS idx_log_errors_user_id ON log_errors(user_id);
