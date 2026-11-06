import { dbPool } from '../../database/postgres.js';
import { redis } from '../../database/redis.js';
import { ConflictError, NotFoundError } from '../../shared/errors/AppError.js';
import { CANONICAL_ACCOUNTS } from '../../shared/constants/defaults.js';
import { z } from 'zod';
import {
  accountResponseSchema,
  createAccountBodySchema,
  updateAccountBodySchema,
} from './accounts.schemas.js';

export class AccountsService {
  private getCacheKey(userId: number): string {
    return `cofrinho:user:${userId}:accounts`;
  }

  async listAccounts(
    userId: number,
    includeHidden = false
  ): Promise<z.infer<typeof accountResponseSchema>[]> {
    const cacheKey = this.getCacheKey(userId);

    /* 1. Tenta recuperar do cache Redis caso não inclua ocultos */
    if (!includeHidden) {
      try {
        const cached = await redis.get(cacheKey);
        if (cached) {
          return JSON.parse(cached);
        }
      } catch {
        /* Fallback para o PostgreSQL */
      }
    }

    /* 2. Consulta no PostgreSQL */
    const statuses = includeHidden ? ['active', 'hidden'] : ['active'];
    const result = await dbPool.query(
      `SELECT id, user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at
       FROM accounts
       WHERE user_id = $1 AND status = ANY($2::varchar[])
       ORDER BY allows_installments DESC, name ASC`,
      [userId, statuses]
    );

    /* 3. Se não houver contas, executa seed canônico */
    if (result.rows.length === 0) {
      await this.seedCanonicalAccounts(userId);
      return this.listAccounts(userId, includeHidden);
    }

    const accounts = result.rows.map((row) => this.mapAccountRow(row));

    /* 4. Grava no cache Redis com TTL de 1 hora */
    if (!includeHidden) {
      try {
        await redis.set(cacheKey, JSON.stringify(accounts), 'EX', 3600);
      } catch {
        /* Redis fallback */
      }
    }

    return accounts;
  }

  async createAccount(userId: number, data: z.infer<typeof createAccountBodySchema>) {
    const nowTimestamp = Date.now();

    /* 1. Verifica duplicidade de nome */
    const existing = await dbPool.query(
      `SELECT id, status FROM accounts WHERE user_id = $1 AND LOWER(name) = LOWER($2)`,
      [userId, data.name]
    );

    if (existing.rows.length > 0) {
      if (existing.rows[0].status === 'deleted') {
        const updated = await dbPool.query(
          `UPDATE accounts
           SET status = 'active', type = $1, icon = $2, color = $3, allows_installments = $4, closing_day = $5, due_day = $6, updated_at = $7
           WHERE id = $8
           RETURNING id, user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at`,
          [
            data.type,
            data.icon,
            data.color,
            data.allows_installments,
            data.closing_day || null,
            data.due_day || null,
            nowTimestamp,
            existing.rows[0].id,
          ]
        );
        await this.invalidateCache(userId);
        return this.mapAccountRow(updated.rows[0]);
      }
      throw new ConflictError(`Já existe uma conta chamada "${data.name}".`);
    }

    /* 2. Insere a conta */
    const result = await dbPool.query(
      `INSERT INTO accounts (user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', $9, $9)
       RETURNING id, user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at`,
      [
        userId,
        data.name,
        data.type,
        data.icon,
        data.color,
        data.allows_installments,
        data.closing_day || null,
        data.due_day || null,
        nowTimestamp,
      ]
    );

    await this.invalidateCache(userId);
    return this.mapAccountRow(result.rows[0]);
  }

  async updateAccount(userId: number, accountId: number, data: z.infer<typeof updateAccountBodySchema>) {
    const nowTimestamp = Date.now();

    const existing = await dbPool.query(
      `SELECT id, name FROM accounts WHERE id = $1 AND user_id = $2`,
      [accountId, userId]
    );

    if (existing.rows.length === 0) {
      throw new NotFoundError('Conta não encontrada ou não pertence a este usuário.');
    }

    if (data.name && data.name.toLowerCase() !== existing.rows[0].name.toLowerCase()) {
      const conflict = await dbPool.query(
        `SELECT id FROM accounts WHERE user_id = $1 AND LOWER(name) = LOWER($2) AND id != $3`,
        [userId, data.name, accountId]
      );
      if (conflict.rows.length > 0) {
        throw new ConflictError(`Já existe uma conta chamada "${data.name}".`);
      }
    }

    const fields: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (data.name !== undefined) {
      fields.push(`name = $${idx++}`);
      values.push(data.name);
    }
    if (data.type !== undefined) {
      fields.push(`type = $${idx++}`);
      values.push(data.type);
    }
    if (data.icon !== undefined) {
      fields.push(`icon = $${idx++}`);
      values.push(data.icon);
    }
    if (data.color !== undefined) {
      fields.push(`color = $${idx++}`);
      values.push(data.color);
    }
    if (data.allows_installments !== undefined) {
      fields.push(`allows_installments = $${idx++}`);
      values.push(data.allows_installments);
    }
    if (data.closing_day !== undefined) {
      fields.push(`closing_day = $${idx++}`);
      values.push(data.closing_day);
    }
    if (data.due_day !== undefined) {
      fields.push(`due_day = $${idx++}`);
      values.push(data.due_day);
    }
    if (data.status !== undefined) {
      fields.push(`status = $${idx++}`);
      values.push(data.status);
    }

    fields.push(`updated_at = $${idx++}`);
    values.push(nowTimestamp);

    values.push(accountId);
    values.push(userId);

    const query = `
      UPDATE accounts
      SET ${fields.join(', ')}
      WHERE id = $${idx++} AND user_id = $${idx}
      RETURNING id, user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at
    `;

    const result = await dbPool.query(query, values);
    await this.invalidateCache(userId);

    return this.mapAccountRow(result.rows[0]);
  }

  async deleteAccount(userId: number, accountId: number) {
    const nowTimestamp = Date.now();

    const result = await dbPool.query(
      `UPDATE accounts
       SET status = 'deleted', updated_at = $1
       WHERE id = $2 AND user_id = $3
       RETURNING id`,
      [nowTimestamp, accountId, userId]
    );

    if (result.rows.length === 0) {
      throw new NotFoundError('Conta não encontrada ou não pertence a este usuário.');
    }

    await this.invalidateCache(userId);
    return { success: true };
  }

  async toggleAccountVisibility(userId: number, accountId: number) {
    const existing = await dbPool.query(
      `SELECT id, status FROM accounts WHERE id = $1 AND user_id = $2`,
      [accountId, userId]
    );

    if (existing.rows.length === 0) {
      throw new NotFoundError('Conta não encontrada.');
    }

    const currentStatus = existing.rows[0].status;
    const newStatus = currentStatus === 'hidden' ? 'active' : 'hidden';

    const result = await dbPool.query(
      `UPDATE accounts
       SET status = $1, updated_at = $2
       WHERE id = $3 AND user_id = $4
       RETURNING id, user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at`,
      [newStatus, Date.now(), accountId, userId]
    );

    await this.invalidateCache(userId);
    return this.mapAccountRow(result.rows[0]);
  }

  private async seedCanonicalAccounts(userId: number): Promise<void> {
    const now = Date.now();
    for (const acc of CANONICAL_ACCOUNTS) {
      await dbPool.query(
        `INSERT INTO accounts (user_id, name, type, icon, color, allows_installments, closing_day, due_day, status, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', $9, $9)
         ON CONFLICT (user_id, name) DO NOTHING`,
        [
          userId,
          acc.name,
          acc.type,
          acc.icon,
          acc.color,
          acc.allows_installments,
          acc.closing_day || null,
          acc.due_day || null,
          now,
        ]
      );
    }
  }

  private async invalidateCache(userId: number): Promise<void> {
    try {
      await redis.del(this.getCacheKey(userId));
    } catch {
      /* Redis fallback */
    }
  }

  private mapAccountRow(row: any) {
    return {
      id: Number(row.id),
      user_id: Number(row.user_id),
      name: row.name,
      type: row.type,
      icon: row.icon,
      color: row.color,
      allows_installments: Boolean(row.allows_installments),
      closing_day: row.closing_day ? Number(row.closing_day) : null,
      due_day: row.due_day ? Number(row.due_day) : null,
      status: row.status,
      created_at: Number(row.created_at),
      updated_at: Number(row.updated_at),
    };
  }
}
