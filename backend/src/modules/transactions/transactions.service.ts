import crypto from 'crypto';
import { dbPool } from '../../database/postgres.js';
import { redis } from '../../database/redis.js';
import { NotFoundError, ValidationError } from '../../shared/errors/AppError.js';
import { z } from 'zod';
import {
  createTransactionBodySchema,
  updateTransactionBodySchema,
  listTransactionsQuerySchema,
} from './transactions.schemas.js';

export class TransactionsService {
  private getSummaryCachePrefix(userId: number): string {
    return `cofrinho:user:${userId}:tx:summary`;
  }

  async createTransaction(userId: number, data: z.infer<typeof createTransactionBodySchema>) {
    const client = await dbPool.connect();

    try {
      await client.query('BEGIN');

      /* 1. Valida se a categoria existe e pertence ao usuário */
      const catResult = await client.query(
        `SELECT id, name, icon, color FROM categories WHERE id = $1 AND user_id = $2 AND status != 'deleted'`,
        [data.category_id, userId]
      );
      if (catResult.rows.length === 0) {
        throw new NotFoundError('Categoria informada não existe ou foi removida.');
      }
      const category = catResult.rows[0];

      /* 2. Valida se a conta existe e pertence ao usuário */
      const accResult = await client.query(
        `SELECT id, name, type, icon, color, allows_installments, closing_day, due_day FROM accounts WHERE id = $1 AND user_id = $2 AND status != 'deleted'`,
        [data.account_id, userId]
      );
      if (accResult.rows.length === 0) {
        throw new NotFoundError('Conta informada não existe ou foi removida.');
      }
      const account = accResult.rows[0];

      const nowTimestamp = Date.now();
      const isInstallment = Boolean(data.installments?.enabled && (data.installments?.count ?? 1) > 1);

      if (isInstallment) {
        if (!account.allows_installments) {
          throw new ValidationError(
            `A conta "${account.name}" não está configurada para aceitar compras parceladas.`
          );
        }

        const totalInstallments = data.installments!.count;
        const groupId = crypto.randomUUID();

        /* Cálculo de centavos precisos */
        const totalCents = Math.round(data.amount * 100);
        const baseCentsPerInstallment = Math.floor(totalCents / totalInstallments);
        const remainderCents = totalCents - baseCentsPerInstallment * totalInstallments;

        /* Cálculo das datas de vencimento de cada fatura */
        const purchaseDate = new Date(data.date);
        const closingDay = account.closing_day || purchaseDate.getDate();
        const dueDay = account.due_day || purchaseDate.getDate();

        /* Determina o mês inicial da 1ª fatura */
        const isAfterClosing = purchaseDate.getDate() > closingDay;
        const initialMonthOffset = isAfterClosing ? 1 : 0;

        const createdTransactions = [];

        for (let i = 0; i < totalInstallments; i++) {
          const installmentNumber = i + 1;
          /* O resto dos centavos é atribuído à 1ª parcela para garantir soma 100% exata */
          const centsThisInstallment = i === 0 ? baseCentsPerInstallment + remainderCents : baseCentsPerInstallment;
          const amountThisInstallment = centsThisInstallment / 100;

          /* Calcula a data de vencimento da fatura para o mês corrente da parcela */
          const targetDate = new Date(purchaseDate);
          targetDate.setMonth(purchaseDate.getMonth() + initialMonthOffset + i);
          /* Garante que o dia não estoure o tamanho do mês (ex: dia 31 em fevereiro) */
          const maxDaysInTargetMonth = new Date(targetDate.getFullYear(), targetDate.getMonth() + 1, 0).getDate();
          targetDate.setDate(Math.min(dueDay, maxDaysInTargetMonth));

          const installmentTimestamp = targetDate.getTime();
          const descriptionWithInstallment = `${data.description} (${installmentNumber}/${totalInstallments})`;

          const insertQuery = `
            INSERT INTO transactions (
              user_id, category_id, account_id, type, amount, description,
              date, has_time, status, is_installment, installment_number,
              total_installments, installment_group_id, created_at, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', true, $9, $10, $11, $12, $12)
            RETURNING id, user_id, category_id, account_id, type, amount, description,
                      date, has_time, status, is_installment, installment_number,
                      total_installments, installment_group_id, created_at, updated_at
          `;

          const rowResult = await client.query(insertQuery, [
            userId,
            data.category_id,
            data.account_id,
            data.type,
            amountThisInstallment,
            descriptionWithInstallment,
            installmentTimestamp,
            data.has_time,
            installmentNumber,
            totalInstallments,
            groupId,
            nowTimestamp,
          ]);

          createdTransactions.push(
            this.mapTransactionRow(rowResult.rows[0], category, account)
          );
        }

        await client.query('COMMIT');
        await this.invalidateUserTransactionsCache(userId);

        /* Retorna a 1ª parcela como principal */
        return createdTransactions[0];
      }

      /* Transação Simples (À Vista) */
      const insertQuery = `
        INSERT INTO transactions (
          user_id, category_id, account_id, type, amount, description,
          date, has_time, status, is_installment, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', false, $9, $9)
        RETURNING id, user_id, category_id, account_id, type, amount, description,
                  date, has_time, status, is_installment, installment_number,
                  total_installments, installment_group_id, created_at, updated_at
      `;

      const result = await client.query(insertQuery, [
        userId,
        data.category_id,
        data.account_id,
        data.type,
        data.amount,
        data.description,
        data.date,
        data.has_time,
        nowTimestamp,
      ]);

      await client.query('COMMIT');
      await this.invalidateUserTransactionsCache(userId);

      return this.mapTransactionRow(result.rows[0], category, account);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async listTransactions(userId: number, filters: z.infer<typeof listTransactionsQuerySchema>) {
    const conditions = ['t.user_id = $1'];
    const values: any[] = [userId];
    let idx = 2;

    if (filters.status === 'all') {
      conditions.push(`t.status != 'deleted'`);
    } else {
      conditions.push(`t.status = $${idx++}`);
      values.push(filters.status);
    }

    if (filters.category_id) {
      conditions.push(`t.category_id = $${idx++}`);
      values.push(filters.category_id);
    }

    if (filters.account_id) {
      conditions.push(`t.account_id = $${idx++}`);
      values.push(filters.account_id);
    }

    /* Filtragem por Mês e Ano */
    if (filters.month && filters.year) {
      const startOfMonth = new Date(Date.UTC(filters.year, filters.month - 1, 1, 0, 0, 0)).getTime();
      const endOfMonth = new Date(Date.UTC(filters.year, filters.month, 0, 23, 59, 59, 999)).getTime();

      conditions.push(`t.date >= $${idx++}`);
      values.push(startOfMonth);

      conditions.push(`t.date <= $${idx++}`);
      values.push(endOfMonth);
    }

    const offset = (filters.page - 1) * filters.limit;
    values.push(filters.limit);
    values.push(offset);

    const query = `
      SELECT
        t.id, t.user_id, t.category_id, t.account_id, t.type, t.amount, t.description,
        t.date, t.has_time, t.status, t.is_installment, t.installment_number,
        t.total_installments, t.installment_group_id, t.created_at, t.updated_at,
        c.name AS category_name, c.icon AS category_icon, c.color AS category_color,
        a.name AS account_name, a.type AS account_type, a.icon AS account_icon, a.color AS account_color
      FROM transactions t
      JOIN categories c ON c.id = t.category_id
      JOIN accounts a ON a.id = t.account_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY t.date DESC, t.id DESC
      LIMIT $${idx++} OFFSET $${idx}
    `;

    const result = await dbPool.query(query, values);

    return result.rows.map((row) =>
      this.mapTransactionRow(row, {
        id: Number(row.category_id),
        name: row.category_name,
        icon: row.category_icon,
        color: row.category_color,
      }, {
        id: Number(row.account_id),
        name: row.account_name,
        type: row.account_type,
        icon: row.account_icon,
        color: row.account_color,
      })
    );
  }

  async getSuggestions(userId: number, query = '') {
    /* Algoritmo de sugestão de descrições frequentes do usuário */
    const trimmed = query.trim();
    const searchPattern = trimmed.length > 0 ? `${trimmed}%` : '%';

    const sql = `
      SELECT
        t.description,
        t.category_id,
        t.account_id,
        COUNT(*)::int AS usage_count,
        MAX(t.date) AS last_used
      FROM transactions t
      WHERE t.user_id = $1 AND t.status != 'deleted' AND t.description ILIKE $2
      GROUP BY t.description, t.category_id, t.account_id
      ORDER BY usage_count DESC, last_used DESC
      LIMIT 6
    `;

    const result = await dbPool.query(sql, [userId, searchPattern]);

    return result.rows.map((row) => ({
      description: row.description,
      suggested_category_id: row.category_id ? Number(row.category_id) : null,
      suggested_account_id: row.account_id ? Number(row.account_id) : null,
      count: Number(row.usage_count),
    }));
  }

  async updateTransaction(userId: number, transactionId: number, data: z.infer<typeof updateTransactionBodySchema>) {
    const nowTimestamp = Date.now();

    const existing = await dbPool.query(
      `SELECT id FROM transactions WHERE id = $1 AND user_id = $2`,
      [transactionId, userId]
    );

    if (existing.rows.length === 0) {
      throw new NotFoundError('Gasto não encontrado ou não pertence a este usuário.');
    }

    const fields: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (data.description !== undefined) {
      fields.push(`description = $${idx++}`);
      values.push(data.description);
    }
    if (data.amount !== undefined) {
      fields.push(`amount = $${idx++}`);
      values.push(data.amount);
    }
    if (data.date !== undefined) {
      fields.push(`date = $${idx++}`);
      values.push(data.date);
    }
    if (data.has_time !== undefined) {
      fields.push(`has_time = $${idx++}`);
      values.push(data.has_time);
    }
    if (data.category_id !== undefined) {
      fields.push(`category_id = $${idx++}`);
      values.push(data.category_id);
    }
    if (data.account_id !== undefined) {
      fields.push(`account_id = $${idx++}`);
      values.push(data.account_id);
    }
    if (data.status !== undefined) {
      fields.push(`status = $${idx++}`);
      values.push(data.status);
    }

    fields.push(`updated_at = $${idx++}`);
    values.push(nowTimestamp);

    values.push(transactionId);
    values.push(userId);

    const query = `
      UPDATE transactions
      SET ${fields.join(', ')}
      WHERE id = $${idx++} AND user_id = $${idx}
      RETURNING id, user_id, category_id, account_id, type, amount, description,
                date, has_time, status, is_installment, installment_number,
                total_installments, installment_group_id, created_at, updated_at
    `;

    const result = await dbPool.query(query, values);
    await this.invalidateUserTransactionsCache(userId);

    return this.mapTransactionRow(result.rows[0]);
  }

  async deleteTransaction(userId: number, transactionId: number, cascade: 'single' | 'all_future' = 'single') {
    const nowTimestamp = Date.now();

    const existing = await dbPool.query(
      `SELECT id, is_installment, installment_group_id, installment_number
       FROM transactions WHERE id = $1 AND user_id = $2`,
      [transactionId, userId]
    );

    if (existing.rows.length === 0) {
      throw new NotFoundError('Gasto não encontrado.');
    }

    const current = existing.rows[0];

    /* Exclusão em cascata para parcelas futuras do mesmo grupo */
    if (cascade === 'all_future' && current.is_installment && current.installment_group_id) {
      await dbPool.query(
        `UPDATE transactions
         SET status = 'deleted', updated_at = $1
         WHERE user_id = $2
           AND installment_group_id = $3
           AND installment_number >= $4`,
        [nowTimestamp, userId, current.installment_group_id, current.installment_number]
      );
    } else {
      await dbPool.query(
        `UPDATE transactions
         SET status = 'deleted', updated_at = $1
         WHERE id = $2 AND user_id = $3`,
        [nowTimestamp, transactionId, userId]
      );
    }

    await this.invalidateUserTransactionsCache(userId);
    return { success: true };
  }

  async toggleTransactionVisibility(userId: number, transactionId: number) {
    const existing = await dbPool.query(
      `SELECT id, status FROM transactions WHERE id = $1 AND user_id = $2`,
      [transactionId, userId]
    );

    if (existing.rows.length === 0) {
      throw new NotFoundError('Gasto não encontrado.');
    }

    const newStatus = existing.rows[0].status === 'hidden' ? 'active' : 'hidden';

    const result = await dbPool.query(
      `UPDATE transactions
       SET status = $1, updated_at = $2
       WHERE id = $3 AND user_id = $4
       RETURNING id, user_id, category_id, account_id, type, amount, description,
                 date, has_time, status, is_installment, installment_number,
                 total_installments, installment_group_id, created_at, updated_at`,
      [newStatus, Date.now(), transactionId, userId]
    );

    await this.invalidateUserTransactionsCache(userId);
    return this.mapTransactionRow(result.rows[0]);
  }

  private async invalidateUserTransactionsCache(userId: number): Promise<void> {
    try {
      /* Invalidação em massa de chaves temporárias do usuário usando SCAN */
      const pattern = `${this.getSummaryCachePrefix(userId)}:*`;
      const stream = redis.scanStream({ match: pattern });
      stream.on('data', async (keys: string[]) => {
        if (keys.length) {
          const pipeline = redis.pipeline();
          keys.forEach((k) => pipeline.del(k));
          await pipeline.exec();
        }
      });
    } catch {
      /* Redis fallback */
    }
  }

  private mapTransactionRow(row: any, category?: any, account?: any) {
    return {
      id: Number(row.id),
      user_id: Number(row.user_id),
      category_id: Number(row.category_id),
      category: category
        ? {
            id: Number(category.id),
            name: category.name,
            icon: category.icon,
            color: category.color,
          }
        : undefined,
      account_id: Number(row.account_id),
      account: account
        ? {
            id: Number(account.id),
            name: account.name,
            type: account.type,
            icon: account.icon,
            color: account.color,
          }
        : undefined,
      type: row.type,
      amount: parseFloat(row.amount),
      description: row.description,
      date: Number(row.date),
      has_time: Boolean(row.has_time),
      status: row.status,
      is_installment: Boolean(row.is_installment),
      installment_number: row.installment_number ? Number(row.installment_number) : null,
      total_installments: row.total_installments ? Number(row.total_installments) : null,
      installment_group_id: row.installment_group_id || null,
      created_at: Number(row.created_at),
      updated_at: Number(row.updated_at),
    };
  }
}

