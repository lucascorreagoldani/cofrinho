-- Cofrinho Database Schema (PostgreSQL)

-- 1. Tabela USERS
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    first_ip VARCHAR(45) NOT NULL,
    last_ip VARCHAR(45) NOT NULL,
    ip_history JSONB NOT NULL DEFAULT '[]'::jsonb,
    first_login TIMESTAMPTZ,
    last_login TIMESTAMPTZ,
    last_session UUID,
    password_hash VARCHAR(255) NOT NULL,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- 2. Tabela USERS_SESSIONS
CREATE TABLE IF NOT EXISTS users_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    login_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    logout_time TIMESTAMPTZ,
    duration INTEGER, -- Duração em segundos
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'revoked')),
    ip VARCHAR(45) NOT NULL,
    user_agent VARCHAR(255),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON users_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON users_sessions(status);

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
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    fast_login BOOLEAN NOT NULL DEFAULT true,      -- "Manter Logado"
    verification BOOLEAN NOT NULL DEFAULT false,   -- "Face ID e Touch ID"
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

