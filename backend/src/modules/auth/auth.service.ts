import bcrypt from 'bcryptjs';
import { dbPool } from '../../database/postgres.js';
import { redis } from '../../database/redis.js';
import { ConflictError, UnauthorizedError } from '../../shared/errors/AppError.js';
import { z } from 'zod';
import { registerBodySchema, loginBodySchema } from './auth.schemas.js';
import { CANONICAL_CATEGORIES, CANONICAL_ACCOUNTS } from '../../shared/constants/defaults.js';

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
        const conflictField = existingUser.rows[0].username === data.username ? 'nome de usuário' : 'e-mail';
        throw new ConflictError(
          `Já existe uma conta cadastrada com este ${conflictField}.`
        );
      }

      /* 2. Hash da senha com salt 12 */
      const passwordHash = await bcrypt.hash(data.password, 12);
      const nowTimestamp = Date.now();

      /* 3. Insere usuário com ID crescente e timestamp em epoch ms */
      const insertUserQuery = `
        INSERT INTO users (username, email, password_hash, first_ip, last_ip, ip_history, registered_at, updated_at)
        VALUES ($1, $2, $3, $4, $4, $5::jsonb, $6, $6)
        RETURNING id, username, email, first_ip, last_ip, registered_at
      `;
      const ipHistoryJson = JSON.stringify([clientIp]);
      const userResult = await client.query(insertUserQuery, [
        data.username,
        data.email,
        passwordHash,
        clientIp,
        ipHistoryJson,
        nowTimestamp,
      ]);

      const newUser = userResult.rows[0];
      const numericUserId = Number(newUser.id);

      /* 4. Cria preferências padrão na tabela users_preferences (1:1) com timestamp numérico */
      await client.query(
        `INSERT INTO users_preferences (user_id, fast_login, verification, updated_at) VALUES ($1, true, false, $2)`,
        [numericUserId, nowTimestamp]
      );

      /* 5. Inicializa as 6 categorias canônicas para o novo usuário */
      for (const cat of CANONICAL_CATEGORIES) {
        await client.query(
          `INSERT INTO categories (user_id, name, icon, color, is_default, status, created_at, updated_at)
           VALUES ($1, $2, $3, $4, true, 'active', $5, $5)
           ON CONFLICT (user_id, name) DO NOTHING`,
          [numericUserId, cat.name, cat.icon, cat.color, nowTimestamp]
        );
      }

      /* 6. Inicializa as contas canônicas para o novo usuário */
      for (const acc of CANONICAL_ACCOUNTS) {
        await client.query(
          `INSERT INTO accounts (user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', $9, $9)
           ON CONFLICT (user_id, name) DO NOTHING`,
          [
            numericUserId,
            acc.name,
            acc.type,
            acc.icon,
            acc.color,
            acc.allows_installments,
            acc.closing_day || null,
            acc.due_day || null,
            nowTimestamp,
          ]
        );
      }

      await client.query('COMMIT');

      return {
        id: numericUserId,
        username: newUser.username,
        email: newUser.email,
        first_ip: newUser.first_ip,
        last_ip: newUser.last_ip,
        first_login: null,
        last_login: null,
        registered_at: Number(newUser.registered_at),
      };
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
        `SELECT id, username, email, password_hash, first_login, ip_history, registered_at FROM users WHERE username = $1 OR email = $1`,
        [data.login]
      );

      if (userResult.rows.length === 0) {
        throw new UnauthorizedError('Usuário/e-mail ou senha incorretos.');
      }

      const user = userResult.rows[0];
      const numericUserId = Number(user.id);

      /* 2. Valida senha */
      const isPasswordValid = await bcrypt.compare(data.password, user.password_hash);
      if (!isPasswordValid) {
        throw new UnauthorizedError('Usuário/e-mail ou senha incorretos.');
      }

      await client.query('BEGIN');

      /* 3. Atualiza histórico de IP e datas de login em epoch ms */
      const ipHistory: string[] = Array.isArray(user.ip_history) ? user.ip_history : [];
      if (!ipHistory.includes(clientIp)) {
        ipHistory.push(clientIp);
      }

      const nowTimestamp = Date.now();
      const isFirstLogin = !user.first_login;

      /* TTL da sessão: 7 dias se fast_login, 24 horas caso contrário */
      const sessionDurationHours = data.fast_login ? 24 * 7 : 24;
      const expiresAt = nowTimestamp + sessionDurationHours * 3600 * 1000;

      /* 4. Cria sessão na tabela users_sessions com timestamps numéricos */
      const sessionResult = await client.query(
        `INSERT INTO users_sessions (user_id, login_time, status, ip, user_agent, expires_at)
         VALUES ($1, $2, 'active', $3, $4, $5)
         RETURNING id, status, expires_at, login_time`,
        [numericUserId, nowTimestamp, clientIp, userAgent, expiresAt]
      );

      const session = sessionResult.rows[0];

      /* 5. Atualiza tabela users com a última sessão e timestamps em epoch ms */
      await client.query(
        `UPDATE users
         SET last_login = $1,
             first_login = COALESCE(first_login, $1),
             last_ip = $2,
             ip_history = $3::jsonb,
             last_session = $4,
             updated_at = $1
         WHERE id = $5`,
        [nowTimestamp, clientIp, JSON.stringify(ipHistory), session.id, numericUserId]
      );

      /* 6. Atualiza preferência de fast_login se fornecida */
      await client.query(
        `UPDATE users_preferences SET fast_login = $1, updated_at = $2 WHERE user_id = $3`,
        [data.fast_login, nowTimestamp, numericUserId]
      );

      await client.query('COMMIT');

      /* 7. Armazena no Redis com namespace canônico cofrinho:session:<id> para validação instantânea (<1ms) */
      try {
        const sessionPayload = JSON.stringify({
          userId: numericUserId,
          username: user.username,
          sessionId: session.id,
          ip: clientIp,
          fastLogin: data.fast_login,
          expiresAt,
          loginTime: nowTimestamp,
        });

        const ttlSeconds = sessionDurationHours * 3600;
        await redis.set(`cofrinho:session:${session.id}`, sessionPayload, 'EX', ttlSeconds);
      } catch (err) {
        console.warn('⚠️ Falha ao salvar sessão no Redis (seguindo apenas com PostgreSQL):', (err as Error).message);
      }

      return {
        user: {
          id: numericUserId,
          username: user.username,
          email: user.email,
          first_ip: user.first_ip || clientIp,
          last_ip: clientIp,
          first_login: user.first_login ? Number(user.first_login) : (isFirstLogin ? nowTimestamp : null),
          last_login: nowTimestamp,
          registered_at: Number(user.registered_at),
        },
        session: {
          id: session.id,
          status: session.status,
          expires_at: Number(session.expires_at),
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
      const nowTimestamp = Date.now();

      /* 1. Atualiza registro na tabela users_sessions com duration em milissegundos */
      const result = await client.query(
        `UPDATE users_sessions
         SET logout_time = $1,
             duration = ($1 - login_time),
             status = 'revoked'
         WHERE id = $2 AND status = 'active'
         RETURNING user_id`,
        [nowTimestamp, sessionId]
      );

      /* 2. Remove da chave canônica do Redis */
      try {
        await redis.del(`cofrinho:session:${sessionId}`);
      } catch (err) {
        console.warn('⚠️ Falha ao remover sessão no Redis:', (err as Error).message);
      }

      return result.rowCount ? result.rowCount > 0 : false;
    } finally {
      client.release();
    }
  }

  async validateSession(sessionId: string): Promise<boolean> {
    /* 1. Tenta validar no Redis primeiro (cache rápido < 1ms) */
    try {
      const cached = await redis.get(`cofrinho:session:${sessionId}`);
      if (cached) {
        const payload = JSON.parse(cached);
        if (payload.expiresAt && payload.expiresAt > Date.now()) {
          return true;
        }
        /* Sessão expirada no payload */
        await redis.del(`cofrinho:session:${sessionId}`);
        return false;
      }
    } catch {
      /* Falha no Redis cai no Postgres de forma não-bloqueante */
    }

    /* 2. Validação no Postgres com timestamp numérico */
    const result = await dbPool.query(
      `SELECT id FROM users_sessions WHERE id = $1 AND status = 'active' AND expires_at > $2`,
      [sessionId, Date.now()]
    );

    return result.rows.length > 0;
  }
}
