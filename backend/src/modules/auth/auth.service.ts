import bcrypt from 'bcryptjs';
import { dbPool } from '../../database/postgres.js';
import { redis } from '../../database/redis.js';
import { AppError } from '../../shared/errors/AppError.js';
import { z } from 'zod';
import { registerBodySchema, loginBodySchema } from './auth.schemas.js';

export class AuthService {
  async register(data: z.infer<typeof registerBodySchema>, clientIp: string) {
    const client = await dbPool.connect();

    try {
      await client.query('BEGIN');

      /* 1. Verifica se já existe usuário ou email */
      const existingUser = await client.query(
        'SELECT id, username, email FROM users WHERE username = $1 OR email = $2',
        [data.username, data.email]
      );

      if (existingUser.rows.length > 0) {
        const conflictField = existingUser.rows[0].username === data.username ? 'username' : 'email';
        throw new AppError(
          'Conflito de Usuário',
          `Já existe uma conta cadastrada com este ${conflictField === 'username' ? 'nome de usuário' : 'e-mail'}.`,
          409,
          'USER_CONFLICT',
          'https://api.cofrinho.app/errors/user-conflict'
        );
      }

      /* 2. Hash da senha com salt 12 */
      const passwordHash = await bcrypt.hash(data.password, 12);

      /* 3. Insere usuário */
      const insertUserQuery = `
        INSERT INTO users (username, email, password_hash, first_ip, last_ip, ip_history, registered_at)
        VALUES ($1, $2, $3, $4, $4, $5::jsonb, NOW())
        RETURNING id, username, email, first_ip, last_ip, registered_at
      `;
      const ipHistoryJson = JSON.stringify([clientIp]);
      const userResult = await client.query(insertUserQuery, [
        data.username,
        data.email,
        passwordHash,
        clientIp,
        ipHistoryJson,
      ]);

      const newUser = userResult.rows[0];

      /* 4. Cria preferências padrão na tabela users_preferences (1:1) */
      await client.query(
        `INSERT INTO users_preferences (user_id, fast_login, verification) VALUES ($1, true, false)`,
        [newUser.id]
      );

      await client.query('COMMIT');

      return newUser;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async login(data: z.infer<typeof loginBodySchema>, clientIp: string, userAgent = 'Unknown') {
    const client = await dbPool.connect();

    try {
      /* 1. Busca usuário por username ou email */
      const userResult = await client.query(
        `SELECT id, username, email, password_hash, first_login, ip_history FROM users WHERE username = $1 OR email = $1`,
        [data.login]
      );

      if (userResult.rows.length === 0) {
        throw new AppError(
          'Credenciais Inválidas',
          'Usuário/e-mail ou senha incorretos.',
          401,
          'INVALID_CREDENTIALS',
          'https://api.cofrinho.app/errors/invalid-credentials'
        );
      }

      const user = userResult.rows[0];

      /* 2. Valida senha */
      const isPasswordValid = await bcrypt.compare(data.password, user.password_hash);
      if (!isPasswordValid) {
        throw new AppError(
          'Credenciais Inválidas',
          'Usuário/e-mail ou senha incorretos.',
          401,
          'INVALID_CREDENTIALS',
          'https://api.cofrinho.app/errors/invalid-credentials'
        );
      }

      await client.query('BEGIN');

      /* 3. Atualiza histórico de IP e datas de login */
      const ipHistory: string[] = Array.isArray(user.ip_history) ? user.ip_history : [];
      if (!ipHistory.includes(clientIp)) {
        ipHistory.push(clientIp);
      }

      const isFirstLogin = !user.first_login;
      const now = new Date();

      /* TTL da sessão (7 dias se fast_login, 24 horas caso contrário) */
      const sessionDurationHours = data.fast_login ? 24 * 7 : 24;
      const expiresAt = new Date(now.getTime() + sessionDurationHours * 60 * 60 * 1000);

      /* 4. Cria sessão na tabela users_sessions */
      const sessionResult = await client.query(
        `INSERT INTO users_sessions (user_id, login_time, status, ip, user_agent, expires_at)
         VALUES ($1, NOW(), 'active', $2, $3, $4)
         RETURNING id, status, expires_at, login_time`,
        [user.id, clientIp, userAgent, expiresAt]
      );

      const session = sessionResult.rows[0];

      /* 5. Atualiza tabela users com a última sessão e datas */
      await client.query(
        `UPDATE users
         SET last_login = NOW(),
             first_login = COALESCE(first_login, NOW()),
             last_ip = $1,
             ip_history = $2::jsonb,
             last_session = $3,
             updated_at = NOW()
         WHERE id = $4`,
        [clientIp, JSON.stringify(ipHistory), session.id, user.id]
      );

      /* 6. Atualiza preferência de fast_login se fornecida */
      await client.query(
        `UPDATE users_preferences SET fast_login = $1, updated_at = NOW() WHERE user_id = $2`,
        [data.fast_login, user.id]
      );

      await client.query('COMMIT');

      /* 7. Armazena no Redis para validação rápida (<1ms) e revogação instantânea */
      try {
        const sessionPayload = JSON.stringify({
          userId: user.id,
          username: user.username,
          sessionId: session.id,
          ip: clientIp,
          fastLogin: data.fast_login,
          expiresAt: expiresAt.toISOString(),
        });

        const ttlSeconds = sessionDurationHours * 60 * 60;
        await redis.set(`session:${session.id}`, sessionPayload, 'EX', ttlSeconds);
      } catch (err) {
        console.warn('⚠️ Falha ao salvar sessão no Redis (seguindo apenas com PostgreSQL):', (err as Error).message);
      }

      return {
        user: {
          id: user.id,
          username: user.username,
          email: user.email,
          first_ip: user.first_ip || clientIp,
          last_ip: clientIp,
          first_login: isFirstLogin ? now.toISOString() : user.first_login,
          last_login: now.toISOString(),
          registered_at: user.registered_at,
        },
        session: {
          id: session.id,
          status: session.status,
          expires_at: session.expires_at.toISOString(),
        },
        sessionDurationHours,
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async logout(sessionId: string) {
    const client = await dbPool.connect();

    try {
      /* 1. Atualiza registro na tabela users_sessions */
      const result = await client.query(
        `UPDATE users_sessions
         SET logout_time = NOW(),
             duration = EXTRACT(EPOCH FROM (NOW() - login_time))::INTEGER,
             status = 'revoked'
         WHERE id = $1 AND status = 'active'
         RETURNING user_id`,
        [sessionId]
      );

      /* 2. Remove do Redis */
      try {
        await redis.del(`session:${sessionId}`);
      } catch (err) {
        console.warn('⚠️ Falha ao remover sessão no Redis:', (err as Error).message);
      }

      return result.rowCount ? result.rowCount > 0 : false;
    } finally {
      client.release();
    }
  }

  async validateSession(sessionId: string): Promise<boolean> {
    /* 1. Tenta validar no Redis primeiro (cache) */
    try {
      const cached = await redis.get(`session:${sessionId}`);
      if (cached) return true;
    } catch {
      /* Falha no Redis cai no Postgres */
    }

    /* 2. Validação no Postgres */
    const result = await dbPool.query(
      `SELECT id FROM users_sessions WHERE id = $1 AND status = 'active' AND expires_at > NOW()`,
      [sessionId]
    );

    return result.rows.length > 0;
  }
}

