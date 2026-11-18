import { dbPool } from '../../database/postgres.js';
import { redis } from '../../database/redis.js';
import { NotFoundError } from '../../shared/errors/AppError.js';
import { TransactionType } from '../../shared/constants/enums.js';
import { z } from 'zod';
import { updatePreferencesBodySchema } from './users.schemas.js';

export class UsersService {
  private getPrefsCacheKey(userId: number): string {
    return `cofrinho:user:${userId}:preferences`;
  }

  private mapPreferencesRow(row: any) {
    return {
      user_id: Number(row.user_id),
      fast_login: Boolean(row.fast_login),
      verification: Boolean(row.verification),
      default_transaction_type: row.default_transaction_type || TransactionType.EXPENSE,
      updated_at: Number(row.updated_at),
    };
  }
  async getProfile(userId: number | string) {
    const numericId = Number(userId);
    const nowTimestamp = Date.now();

    const result = await dbPool.query(
      `UPDATE users
       SET last_login = $2,
           first_login = COALESCE(first_login, $2),
           updated_at = $2
       WHERE id = $1
       RETURNING id, username, email, first_ip, last_ip, first_login, last_login, registered_at`,
      [numericId, nowTimestamp]
    );

    if (result.rows.length === 0) {
      throw new NotFoundError('A conta solicitada não existe.');
    }

    const row = result.rows[0];
    return {
      id: Number(row.id),
      username: row.username,
      email: row.email,
      first_ip: row.first_ip,
      last_ip: row.last_ip,
      first_login: row.first_login ? Number(row.first_login) : null,
      last_login: row.last_login ? Number(row.last_login) : null,
      registered_at: Number(row.registered_at),
    };
  }

  async getPreferences(userId: number | string) {
    const numericId = Number(userId);
    const cacheKey = this.getPrefsCacheKey(numericId);

    try {
      const cached = await redis.get(cacheKey);
      if (cached) {
        const parsed = JSON.parse(cached);
        if (parsed && parsed.default_transaction_type) {
          return parsed;
        }
      }
    } catch {
      /* Fallback resiliente para PostgreSQL caso o Redis oscile */
    }

    const result = await dbPool.query(
      `SELECT user_id, fast_login, verification, default_transaction_type, updated_at
       FROM users_preferences WHERE user_id = $1`,
      [numericId]
    );

    let prefs;
    if (result.rows.length === 0) {
      const nowTimestamp = Date.now();
      /* Cria padrão se não existir por consistência */
      const insert = await dbPool.query(
        `INSERT INTO users_preferences (user_id, fast_login, verification, default_transaction_type, updated_at)
         VALUES ($1, true, false, $2, $3)
         RETURNING user_id, fast_login, verification, default_transaction_type, updated_at`,
        [numericId, TransactionType.EXPENSE, nowTimestamp]
      );
      prefs = this.mapPreferencesRow(insert.rows[0]);
    } else {
      prefs = this.mapPreferencesRow(result.rows[0]);
    }

    try {
      await redis.set(cacheKey, JSON.stringify(prefs), 'EX', 3600);
    } catch {
      /* Redis fallback */
    }

    return prefs;
  }

  async updatePreferences(userId: number | string, data: z.infer<typeof updatePreferencesBodySchema>) {
    const numericId = Number(userId);
    const updates: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (data.fast_login !== undefined) {
      updates.push(`fast_login = $${idx++}`);
      values.push(data.fast_login);
    }

    if (data.verification !== undefined) {
      updates.push(`verification = $${idx++}`);
      values.push(data.verification);
    }

    if (data.default_transaction_type !== undefined) {
      updates.push(`default_transaction_type = $${idx++}`);
      values.push(data.default_transaction_type);
    }

    const nowTimestamp = Date.now();
    updates.push(`updated_at = $${idx++}`);
    values.push(nowTimestamp);

    values.push(numericId);

    const query = `
      UPDATE users_preferences
      SET ${updates.join(', ')}
      WHERE user_id = $${idx}
      RETURNING user_id, fast_login, verification, default_transaction_type, updated_at
    `;

    const result = await dbPool.query(query, values);
    if (result.rows.length === 0) {
      throw new NotFoundError('Preferências não encontradas para o usuário.');
    }

    const prefs = this.mapPreferencesRow(result.rows[0]);

    try {
      await redis.set(this.getPrefsCacheKey(numericId), JSON.stringify(prefs), 'EX', 3600);
    } catch {
      /* Redis fallback */
    }

    return prefs;
  }

  async listSessions(userId: number | string, currentSessionId: string, limit: number, cursor?: string) {
    const numericId = Number(userId);
    const params: any[] = [numericId, limit + 1];
    let cursorClause = '';

    if (cursor) {
      params.push(cursor);
      cursorClause = `AND login_time < (SELECT login_time FROM users_sessions WHERE id = $3)`;
    }

    const query = `
      SELECT id, login_time, logout_time, duration, status, ip, user_agent
      FROM users_sessions
      WHERE user_id = $1 ${cursorClause}
      ORDER BY login_time DESC
      LIMIT $2
    `;

    const result = await dbPool.query(query, params);
    const hasMore = result.rows.length > limit;
    const items = hasMore ? result.rows.slice(0, limit) : result.rows;

    const formattedItems = items.map((row: any) => ({
      id: row.id,
      login_time: Number(row.login_time),
      logout_time: row.logout_time ? Number(row.logout_time) : null,
      duration: row.duration ? Number(row.duration) : null,
      status: row.status,
      ip: row.ip,
      user_agent: row.user_agent,
      is_current: row.id === currentSessionId,
    }));

    const nextCursor = hasMore && items.length > 0 ? items[items.length - 1].id : null;

    return {
      data: formattedItems,
      pagination: {
        limit,
        next_cursor: nextCursor,
        has_more: hasMore,
      },
    };
  }
}
