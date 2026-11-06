import { dbPool } from '../../database/postgres.js';
import { AppError } from '../../shared/errors/AppError.js';
import { z } from 'zod';
import { updatePreferencesBodySchema } from './users.schemas.js';

export class UsersService {
  async getProfile(userId: string) {
    const result = await dbPool.query(
      `SELECT id, username, email, first_ip, last_ip, first_login, last_login, registered_at
       FROM users WHERE id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      throw new AppError('Usuário não encontrado', 'A conta solicitada não existe.', 404, 'USER_NOT_FOUND');
    }

    const row = result.rows[0];
    return {
      ...row,
      registered_at: row.registered_at.toISOString(),
      first_login: row.first_login ? row.first_login.toISOString() : null,
      last_login: row.last_login ? row.last_login.toISOString() : null,
    };
  }

  async getPreferences(userId: string) {
    const result = await dbPool.query(
      `SELECT user_id, fast_login, verification, updated_at
       FROM users_preferences WHERE user_id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      /* Cria padrão se não existir por consistência */
      const insert = await dbPool.query(
        `INSERT INTO users_preferences (user_id, fast_login, verification)
         VALUES ($1, true, false)
         RETURNING user_id, fast_login, verification, updated_at`,
        [userId]
      );
      const row = insert.rows[0];
      return { ...row, updated_at: row.updated_at.toISOString() };
    }

    const row = result.rows[0];
    return {
      user_id: row.user_id,
      fast_login: row.fast_login,
      verification: row.verification,
      updated_at: row.updated_at.toISOString(),
    };
  }

  async updatePreferences(userId: string, data: z.infer<typeof updatePreferencesBodySchema>) {
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

    updates.push(`updated_at = NOW()`);
    values.push(userId);

    const query = `
      UPDATE users_preferences
      SET ${updates.join(', ')}
      WHERE user_id = $${idx}
      RETURNING user_id, fast_login, verification, updated_at
    `;

    const result = await dbPool.query(query, values);
    const row = result.rows[0];
    return {
      user_id: row.user_id,
      fast_login: row.fast_login,
      verification: row.verification,
      updated_at: row.updated_at.toISOString(),
    };
  }

  async listSessions(userId: string, currentSessionId: string, limit: number, cursor?: string) {
    const params: any[] = [userId, limit + 1];
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
      login_time: row.login_time.toISOString(),
      logout_time: row.logout_time ? row.logout_time.toISOString() : null,
      duration: row.duration,
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

