import { dbPool } from '../../database/postgres.js';
import { NotFoundError } from '../../shared/errors/AppError.js';
import { z } from 'zod';
import { updatePreferencesBodySchema } from './users.schemas.js';

export class UsersService {
  async getProfile(userId: number | string) {
    const numericId = Number(userId);

    const result = await dbPool.query(
      `SELECT id, username, email, first_ip, last_ip, first_login, last_login, registered_at
       FROM users WHERE id = $1`,
      [numericId]
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

    const result = await dbPool.query(
      `SELECT user_id, fast_login, verification, updated_at
       FROM users_preferences WHERE user_id = $1`,
      [numericId]
    );

    if (result.rows.length === 0) {
      const nowTimestamp = Date.now();
      /* Cria padrão se não existir por consistência */
      const insert = await dbPool.query(
        `INSERT INTO users_preferences (user_id, fast_login, verification, updated_at)
         VALUES ($1, true, false, $2)
         RETURNING user_id, fast_login, verification, updated_at`,
        [numericId, nowTimestamp]
      );
      const row = insert.rows[0];
      return {
        user_id: Number(row.user_id),
        fast_login: row.fast_login,
        verification: row.verification,
        updated_at: Number(row.updated_at),
      };
    }

    const row = result.rows[0];
    return {
      user_id: Number(row.user_id),
      fast_login: row.fast_login,
      verification: row.verification,
      updated_at: Number(row.updated_at),
    };
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

    const nowTimestamp = Date.now();
    updates.push(`updated_at = $${idx++}`);
    values.push(nowTimestamp);

    values.push(numericId);

    const query = `
      UPDATE users_preferences
      SET ${updates.join(', ')}
      WHERE user_id = $${idx}
      RETURNING user_id, fast_login, verification, updated_at
    `;

    const result = await dbPool.query(query, values);
    if (result.rows.length === 0) {
      throw new NotFoundError('Preferências não encontradas para o usuário.');
    }

    const row = result.rows[0];
    return {
      user_id: Number(row.user_id),
      fast_login: row.fast_login,
      verification: row.verification,
      updated_at: Number(row.updated_at),
    };
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
