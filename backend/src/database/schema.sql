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

-- 5. Tabela CATEGORIES (Categorias de Gastos e Receitas por Usuário)
CREATE TABLE IF NOT EXISTS categories (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(60) NOT NULL DEFAULT 'tag.fill',
    color VARCHAR(20) NOT NULL DEFAULT '#FF9500',
    is_default BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'hidden', 'deleted')),
    created_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    updated_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    CONSTRAINT uq_categories_user_name UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_categories_user_status ON categories(user_id, status);

-- 6. Tabela ACCOUNTS (Contas, Cartões, Bancos e Carteiras)
CREATE TABLE IF NOT EXISTS accounts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(30) NOT NULL CHECK (type IN ('credit_card', 'bank_account', 'wallet', 'pix', 'cash')),
    icon VARCHAR(60) NOT NULL DEFAULT 'creditcard.fill',
    color VARCHAR(20) NOT NULL DEFAULT '#007AFF',
    allows_installments BOOLEAN NOT NULL DEFAULT false,
    closing_day SMALLINT CHECK (closing_day BETWEEN 1 AND 31),
    due_day SMALLINT CHECK (due_day BETWEEN 1 AND 31),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'hidden', 'deleted')),
    created_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    updated_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    CONSTRAINT uq_accounts_user_name UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_accounts_user_status ON accounts(user_id, status);

-- 7. Tabela TRANSACTIONS (Gastos e Receitas com Suporte a Parcelamento)
CREATE TABLE IF NOT EXISTS transactions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id BIGINT NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    type VARCHAR(20) NOT NULL DEFAULT 'expense' CHECK (type IN ('expense', 'income')),
    amount NUMERIC(15, 2) NOT NULL CHECK (amount > 0),
    description VARCHAR(255) NOT NULL,
    date BIGINT NOT NULL,
    has_time BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'hidden', 'deleted')),
    is_installment BOOLEAN NOT NULL DEFAULT false,
    installment_number SMALLINT,
    total_installments SMALLINT,
    installment_group_id UUID,
    created_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint,
    updated_at BIGINT NOT NULL DEFAULT (extract(epoch from now()) * 1000)::bigint
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_user_status ON transactions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id);
CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_transactions_group ON transactions(installment_group_id);
CREATE INDEX IF NOT EXISTS idx_transactions_description_search ON transactions(user_id, description);
