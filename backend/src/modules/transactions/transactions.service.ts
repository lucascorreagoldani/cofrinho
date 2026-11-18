import crypto from 'crypto';
import { dbPool } from '../../database/postgres.js';
import { redis } from '../../database/redis.js';
import { NotFoundError, ValidationError } from '../../shared/errors/AppError.js';
import { z } from 'zod';
import {
  DeleteCascadeMode,
  RecordStatus,
  TransactionFilterStatus,
} from '../../shared/constants/enums.js';
import {
  createTransactionBodySchema,
  updateTransactionBodySchema,
  listTransactionsQuerySchema,
} from './transactions.schemas.js';

export class TransactionsService {
  private readonly joinedTransactionSelectSql = `
    SELECT
      t.id, t.user_id, t.category_id, t.account_id, t.type, t.amount, t.description, t.notes,
      t.date, t.has_time, t.status, t.is_installment, t.installment_number,
      t.total_installments, t.installment_group_id,
      t.is_modified, t.modified_at, t.created_by_user_id, t.updated_by_user_id,
      t.created_at, t.updated_at,
      c.name AS category_name, c.icon AS category_icon, c.color AS category_color,
      a.name AS account_name, a.type AS account_type, a.icon AS account_icon, a.color AS account_color,
      u_cre.username AS created_by_username,
      u_mod.username AS updated_by_username
    FROM transactions t
    JOIN categories c ON c.id = t.category_id
    JOIN accounts a ON a.id = t.account_id
    LEFT JOIN users u_cre ON u_cre.id = COALESCE(t.created_by_user_id, t.user_id)
    LEFT JOIN users u_mod ON u_mod.id = t.updated_by_user_id
  `;

  private getTxCachePrefix(userId: number): string {
    return `cofrinho:user:${userId}:tx`;
  }

  private getTxListCacheKey(
    userId: number,
    filters: z.infer<typeof listTransactionsQuerySchema>
  ): string {
    return `${this.getTxCachePrefix(userId)}:list:m${filters.month ?? 'all'}:y${filters.year ?? 'all'}:s${filters.status}:c${filters.category_id ?? 'all'}:a${filters.account_id ?? 'all'}:p${filters.page}:l${filters.limit}`;
  }

  private getTxGroupCacheKey(userId: number, groupId: string): string {
    return `${this.getTxCachePrefix(userId)}:group:${groupId}`;
  }

  private getTxItemCacheKey(userId: number, transactionId: number): string {
    return `${this.getTxCachePrefix(userId)}:item:${transactionId}`;
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

      const creatorResult = await client.query(
        `SELECT id, username FROM users WHERE id = $1`,
        [userId]
      );
      const createdBy =
        creatorResult.rows.length > 0
          ? { id: Number(creatorResult.rows[0].id), username: creatorResult.rows[0].username }
          : { id: userId, username: 'usuario' };

      const nowTimestamp = Date.now();
      const cleanNotes = data.notes && data.notes.trim().length > 0 ? data.notes.trim() : null;
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
              user_id, created_by_user_id, category_id, account_id, type, amount, description, notes,
              date, has_time, status, is_installment, installment_number,
              total_installments, installment_group_id, created_at, updated_at
            )
            VALUES ($1, $1, $2, $3, $4, $5, $6, $7, $8, $9, 'active', true, $10, $11, $12, $13, $13)
            RETURNING id, user_id, created_by_user_id, category_id, account_id, type, amount, description, notes,
                      date, has_time, status, is_installment, installment_number,
                      total_installments, installment_group_id,
                      is_modified, modified_at, updated_by_user_id, created_at, updated_at
          `;

          const rowResult = await client.query(insertQuery, [
            userId,
            data.category_id,
            data.account_id,
            data.type,
            amountThisInstallment,
            descriptionWithInstallment,
            cleanNotes,
            installmentTimestamp,
            data.has_time,
            installmentNumber,
            totalInstallments,
            groupId,
            nowTimestamp,
          ]);

          createdTransactions.push(
            this.mapTransactionRow(rowResult.rows[0], category, account, createdBy, null)
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
          user_id, created_by_user_id, category_id, account_id, type, amount, description, notes,
          date, has_time, status, is_installment, created_at, updated_at
        )
        VALUES ($1, $1, $2, $3, $4, $5, $6, $7, $8, $9, 'active', false, $10, $10)
        RETURNING id, user_id, created_by_user_id, category_id, account_id, type, amount, description, notes,
                  date, has_time, status, is_installment, installment_number,
                  total_installments, installment_group_id,
                  is_modified, modified_at, updated_by_user_id, created_at, updated_at
      `;

      const result = await client.query(insertQuery, [
        userId,
        data.category_id,
        data.account_id,
        data.type,
        data.amount,
        data.description,
        cleanNotes,
        data.date,
        data.has_time,
        nowTimestamp,
      ]);

      await client.query('COMMIT');
      await this.invalidateUserTransactionsCache(userId);

      return this.mapTransactionRow(result.rows[0], category, account, createdBy, null);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async listTransactions(userId: number, filters: z.infer<typeof listTransactionsQuerySchema>) {
    const cacheKey = this.getTxListCacheKey(userId, filters);

    try {
      const cached = await redis.get(cacheKey);
      if (cached) {
        return JSON.parse(cached);
      }
    } catch {
      /* Fallback resiliente para PostgreSQL se o Redis oscilar */
    }

    const conditions = ['t.user_id = $1'];
    const values: any[] = [userId];
    let idx = 2;

    if (filters.status === TransactionFilterStatus.ALL) {
      conditions.push(`t.status != '${RecordStatus.DELETED}'`);
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
      ${this.joinedTransactionSelectSql}
      WHERE ${conditions.join(' AND ')}
      ORDER BY t.date DESC, t.id DESC
      LIMIT $${idx++} OFFSET $${idx}
    `;

    const result = await dbPool.query(query, values);
    const items = result.rows.map((row) => this.mapJoinedTransactionRow(row));

    try {
      await redis.set(cacheKey, JSON.stringify(items), 'EX', 120);
    } catch {
      /* Redis fallback */
    }

    return items;
  }

  /**
   * Lista todas as parcelas associadas a um mesmo installment_group_id em ordem cronológica.
   */
  async listInstallmentGroup(userId: number, groupId: string) {
    const cacheKey = this.getTxGroupCacheKey(userId, groupId);

    try {
      const cached = await redis.get(cacheKey);
      if (cached) {
        return JSON.parse(cached);
      }
    } catch {
      /* Fallback resiliente para PostgreSQL se o Redis oscilar */
    }

    const query = `
      ${this.joinedTransactionSelectSql}
      WHERE t.user_id = $1
        AND t.installment_group_id = $2
        AND t.status != '${RecordStatus.DELETED}'
      ORDER BY t.installment_number ASC, t.date ASC
    `;

    const result = await dbPool.query(query, [userId, groupId]);
    if (result.rows.length === 0) {
      throw new NotFoundError('Parcelamento não encontrado.');
    }

    const items = result.rows.map((row) => this.mapJoinedTransactionRow(row));

    try {
      await redis.set(cacheKey, JSON.stringify(items), 'EX', 120);
    } catch {
      /* Redis fallback */
    }

    return items;
  }

  private cleanSuggestionDescription(raw: string): string {
    let cleaned = raw.trim();
    /* Remove sufixos de parcelamento no formato (1/2), (2/10), etc. */
    cleaned = cleaned.replace(/\s*\(\d+\s*\/\s*\d+\)\s*$/g, '');
    /* Remove sufixos de quantidade no formato (2x), 2x, 10X, etc. */
    cleaned = cleaned.replace(/\s*\(\d+\s*[xX]\)\s*$/g, '');
    cleaned = cleaned.replace(/\s+\d+\s*[xX]\s*$/g, '');
    cleaned = cleaned.replace(/\s+/g, ' ').trim();
    return cleaned.length > 0 ? cleaned : raw.trim();
  }

  async getSuggestions(userId: number, query = '') {
    /* Algoritmo preditivo multifatorial: analisa horário, dia da semana, demanda e recência */
    const normalizedQuery = query.trim().toLowerCase();

    const sql = `
      SELECT
        t.description,
        t.category_id,
        t.account_id,
        t.date,
        t.created_at
      FROM transactions t
      WHERE t.user_id = $1
        AND t.status != 'deleted'
        AND (t.is_installment = false OR t.installment_number = 1)
      ORDER BY t.created_at DESC
      LIMIT 250
    `;

    const result = await dbPool.query(sql, [userId]);

    const nowMs = Date.now();
    const nowDate = new Date(nowMs);
    const nowHour = nowDate.getHours() + nowDate.getMinutes() / 60;
    const nowDayOfWeek = nowDate.getDay();
    const nowIsWeekend = nowDayOfWeek === 0 || nowDayOfWeek === 6;

    interface GroupedSuggestion {
      displayName: string;
      count: number;
      lastCreatedAt: number;
      maxTimeBonus: number;
      timeAffinitySum: number;
      maxDayBonus: number;
      dayAffinitySum: number;
      categoryCounts: Map<number, number>;
      accountCounts: Map<number, number>;
    }

    const groups = new Map<string, GroupedSuggestion>();

    for (const row of result.rows) {
      const cleanDesc = this.cleanSuggestionDescription(String(row.description || ''));
      const key = cleanDesc.toLowerCase();
      if (!key) {
        continue;
      }

      const txTimestamp = Number(row.created_at || row.date || nowMs);
      const txDate = new Date(txTimestamp);
      const txHour = txDate.getHours() + txDate.getMinutes() / 60;
      const txDayOfWeek = txDate.getDay();
      const txIsWeekend = txDayOfWeek === 0 || txDayOfWeek === 6;

      /* Diferença circular em horas (0..12h) */
      const rawHourDiff = Math.abs(nowHour - txHour);
      const circularHourDiff = Math.min(rawHourDiff, 24 - rawHourDiff);

      let timeBonus = 0;
      if (circularHourDiff <= 1) {
        timeBonus = 35;
      } else if (circularHourDiff <= 3) {
        timeBonus = 20;
      } else if (circularHourDiff <= 5) {
        timeBonus = 8;
      }

      /* Afinidade pelo mesmo dia da semana ou mesmo regime (dia útil vs. fim de semana) */
      let dayBonus = 0;
      if (txDayOfWeek === nowDayOfWeek) {
        dayBonus = 20;
      } else if (txIsWeekend === nowIsWeekend) {
        dayBonus = 8;
      }

      let group = groups.get(key);
      if (!group) {
        group = {
          displayName: cleanDesc,
          count: 0,
          lastCreatedAt: txTimestamp,
          maxTimeBonus: 0,
          timeAffinitySum: 0,
          maxDayBonus: 0,
          dayAffinitySum: 0,
          categoryCounts: new Map<number, number>(),
          accountCounts: new Map<number, number>(),
        };
        groups.set(key, group);
      }

      group.count += 1;
      if (txTimestamp > group.lastCreatedAt) {
        group.lastCreatedAt = txTimestamp;
        group.displayName = cleanDesc;
      }
      group.maxTimeBonus = Math.max(group.maxTimeBonus, timeBonus);
      group.timeAffinitySum += timeBonus;
      group.maxDayBonus = Math.max(group.maxDayBonus, dayBonus);
      group.dayAffinitySum += dayBonus;

      if (row.category_id) {
        const catId = Number(row.category_id);
        group.categoryCounts.set(catId, (group.categoryCounts.get(catId) ?? 0) + 1);
      }
      if (row.account_id) {
        const accId = Number(row.account_id);
        group.accountCounts.set(accId, (group.accountCounts.get(accId) ?? 0) + 1);
      }
    }

    const pickTopId = (counts: Map<number, number>): number | null => {
      let bestId: number | null = null;
      let bestCount = -1;
      for (const [id, count] of counts.entries()) {
        if (count > bestCount) {
          bestCount = count;
          bestId = id;
        }
      }
      return bestId;
    };

    const scored: Array<{
      description: string;
      suggested_category_id: number | null;
      suggested_account_id: number | null;
      count: number;
      score: number;
      lastCreatedAt: number;
    }> = [];

    for (const [key, group] of groups.entries()) {
      if (normalizedQuery.length > 0 && !key.includes(normalizedQuery)) {
        continue;
      }

      const avgTimeBonus = group.timeAffinitySum / group.count;
      const avgDayBonus = group.dayAffinitySum / group.count;
      const timeScore = group.maxTimeBonus * 0.65 + avgTimeBonus * 0.35;
      const dayScore = group.maxDayBonus * 0.7 + avgDayBonus * 0.3;

      const daysSinceLast = Math.max(0, (nowMs - group.lastCreatedAt) / (1000 * 60 * 60 * 24));
      const recencyScore = 35 * Math.exp(-daysSinceLast / 14);
      const demandScore = Math.min(30, Math.log2(group.count + 1) * 12);

      let queryBonus = 0;
      if (normalizedQuery.length > 0 && key.startsWith(normalizedQuery)) {
        queryBonus = 25;
      }

      const totalScore = timeScore + dayScore + recencyScore + demandScore + queryBonus;

      scored.push({
        description: group.displayName,
        suggested_category_id: pickTopId(group.categoryCounts),
        suggested_account_id: pickTopId(group.accountCounts),
        count: group.count,
        score: totalScore,
        lastCreatedAt: group.lastCreatedAt,
      });
    }

    scored.sort((a, b) => {
      if (Math.abs(b.score - a.score) > 0.001) {
        return b.score - a.score;
      }
      return b.lastCreatedAt - a.lastCreatedAt;
    });

    return scored.slice(0, 8).map((item) => ({
      description: item.description,
      suggested_category_id: item.suggested_category_id,
      suggested_account_id: item.suggested_account_id,
      count: item.count,
    }));
  }

  async updateTransaction(userId: number, transactionId: number, data: z.infer<typeof updateTransactionBodySchema>) {
    const client = await dbPool.connect();

    try {
      await client.query('BEGIN');

      const existing = await client.query(
        `SELECT id, user_id, category_id, account_id, type, amount, description, notes,
                date, has_time, status, is_installment, installment_number,
                total_installments, installment_group_id,
                is_modified, modified_at, updated_by_user_id, created_at, updated_at
         FROM transactions
         WHERE id = $1 AND user_id = $2 AND status != $3
         FOR UPDATE`,
        [transactionId, userId, RecordStatus.DELETED]
      );

      if (existing.rows.length === 0) {
        throw new NotFoundError('Gasto não encontrado ou não pertence a este usuário.');
      }

      const currentRow = existing.rows[0];
      const previousSnapshot = {
        category_id: Number(currentRow.category_id),
        account_id: Number(currentRow.account_id),
        type: currentRow.type,
        amount: parseFloat(currentRow.amount),
        description: currentRow.description,
        notes: currentRow.notes ?? null,
        date: Number(currentRow.date),
        has_time: Boolean(currentRow.has_time),
        status: currentRow.status,
        is_modified: Boolean(currentRow.is_modified),
        modified_at: currentRow.modified_at ? Number(currentRow.modified_at) : null,
        updated_by_user_id: currentRow.updated_by_user_id ? Number(currentRow.updated_by_user_id) : null,
      };

      if (data.category_id !== undefined) {
        const catCheck = await client.query(
          `SELECT id FROM categories WHERE id = $1 AND user_id = $2 AND status != $3`,
          [data.category_id, userId, RecordStatus.DELETED]
        );
        if (catCheck.rows.length === 0) {
          throw new NotFoundError('Categoria informada não existe ou foi removida.');
        }
      }

      if (data.account_id !== undefined) {
        const accCheck = await client.query(
          `SELECT id FROM accounts WHERE id = $1 AND user_id = $2 AND status != $3`,
          [data.account_id, userId, RecordStatus.DELETED]
        );
        if (accCheck.rows.length === 0) {
          throw new NotFoundError('Conta informada não existe ou foi removida.');
        }
      }

      const fields: string[] = [];
      const values: any[] = [];
      let idx = 1;

      if (data.description !== undefined) {
        fields.push(`description = $${idx++}`);
        values.push(data.description);
      }
      if (data.notes !== undefined) {
        const cleanNotes = data.notes && data.notes.trim().length > 0 ? data.notes.trim() : null;
        fields.push(`notes = $${idx++}`);
        values.push(cleanNotes);
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
      if (data.type !== undefined) {
        fields.push(`type = $${idx++}`);
        values.push(data.type);
      }
      if (data.status !== undefined) {
        fields.push(`status = $${idx++}`);
        values.push(data.status);
      }

      if (fields.length === 0) {
        throw new ValidationError('Nenhum campo válido enviado para atualização.');
      }

      const nowTimestamp = Date.now();
      fields.push(`is_modified = true`);
      fields.push(`modified_at = $${idx++}`);
      values.push(nowTimestamp);
      fields.push(`updated_at = $${idx++}`);
      values.push(nowTimestamp);
      fields.push(`updated_by_user_id = $${idx++}`);
      values.push(userId);

      values.push(transactionId);
      values.push(userId);

      const updateQuery = `
        UPDATE transactions
        SET ${fields.join(', ')}
        WHERE id = $${idx++} AND user_id = $${idx}
        RETURNING id, user_id, category_id, account_id, type, amount, description, notes,
                  date, has_time, status, is_installment, installment_number,
                  total_installments, installment_group_id,
                  is_modified, modified_at, updated_by_user_id, created_at, updated_at
      `;

      const updatedResult = await client.query(updateQuery, values);
      const updatedRow = updatedResult.rows[0];

      const updatedSnapshot = {
        category_id: Number(updatedRow.category_id),
        account_id: Number(updatedRow.account_id),
        type: updatedRow.type,
        amount: parseFloat(updatedRow.amount),
        description: updatedRow.description,
        notes: updatedRow.notes ?? null,
        date: Number(updatedRow.date),
        has_time: Boolean(updatedRow.has_time),
        status: updatedRow.status,
        is_modified: true,
        modified_at: nowTimestamp,
        updated_by_user_id: userId,
      };

      await client.query(
        `INSERT INTO transaction_modifications (
          transaction_id, user_id, previous_snapshot, updated_snapshot, modified_at
        ) VALUES ($1, $2, $3::jsonb, $4::jsonb, $5)`,
        [
          transactionId,
          userId,
          JSON.stringify(previousSnapshot),
          JSON.stringify(updatedSnapshot),
          nowTimestamp,
        ]
      );

      const fullUpdated = await this.fetchFullTransactionById(client, userId, transactionId);

      await client.query('COMMIT');

      await this.invalidateUserTransactionsCache(userId);
      try {
        await redis.set(
          this.getTxItemCacheKey(userId, transactionId),
          JSON.stringify(fullUpdated),
          'EX',
          300
        );
      } catch {
        /* Redis fallback */
      }

      return fullUpdated;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async deleteTransaction(userId: number, transactionId: number, cascade: DeleteCascadeMode = DeleteCascadeMode.SINGLE) {
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
    if (cascade === DeleteCascadeMode.ALL_FUTURE && current.is_installment && current.installment_group_id) {
      await dbPool.query(
        `UPDATE transactions
         SET status = $1, updated_at = $2
         WHERE user_id = $3
           AND installment_group_id = $4
           AND installment_number >= $5`,
        [RecordStatus.DELETED, nowTimestamp, userId, current.installment_group_id, current.installment_number]
      );
    } else {
      await dbPool.query(
        `UPDATE transactions
         SET status = $1, updated_at = $2
         WHERE id = $3 AND user_id = $4`,
        [RecordStatus.DELETED, nowTimestamp, transactionId, userId]
      );
    }

    await this.invalidateUserTransactionsCache(userId);
    return { success: true };
  }

  async toggleTransactionVisibility(userId: number, transactionId: number) {
    const existing = await dbPool.query(
      `SELECT id, status FROM transactions WHERE id = $1 AND user_id = $2 AND status != $3`,
      [transactionId, userId, RecordStatus.DELETED]
    );

    if (existing.rows.length === 0) {
      throw new NotFoundError('Gasto não encontrado.');
    }

    const newStatus = existing.rows[0].status === RecordStatus.HIDDEN ? RecordStatus.ACTIVE : RecordStatus.HIDDEN;

    await dbPool.query(
      `UPDATE transactions
       SET status = $1, updated_at = $2
       WHERE id = $3 AND user_id = $4`,
      [newStatus, Date.now(), transactionId, userId]
    );

    const fullUpdated = await this.fetchFullTransactionById(dbPool, userId, transactionId);

    await this.invalidateUserTransactionsCache(userId);
    try {
      await redis.set(
        this.getTxItemCacheKey(userId, transactionId),
        JSON.stringify(fullUpdated),
        'EX',
        300
      );
    } catch {
      /* Redis fallback */
    }

    return fullUpdated;
  }

  private async fetchFullTransactionById(
    runner: { query: (text: string, params?: any[]) => Promise<{ rows: any[] }> },
    userId: number,
    transactionId: number
  ) {
    const query = `
      ${this.joinedTransactionSelectSql}
      WHERE t.id = $1 AND t.user_id = $2
    `;

    const result = await runner.query(query, [transactionId, userId]);
    if (result.rows.length === 0) {
      throw new NotFoundError('Gasto não encontrado.');
    }

    return this.mapJoinedTransactionRow(result.rows[0]);
  }

  private async invalidateUserTransactionsCache(userId: number): Promise<void> {
    try {
      /* Invalidação síncrona e garantida em massa via SCAN + PIPELINE DEL antes de responder ao cliente */
      const pattern = `${this.getTxCachePrefix(userId)}:*`;
      let cursor = '0';
      do {
        const [nextCursor, keys] = await redis.scan(cursor, 'MATCH', pattern, 'COUNT', 100);
        cursor = nextCursor;
        if (keys.length > 0) {
          const pipeline = redis.pipeline();
          keys.forEach((k) => pipeline.del(k));
          await pipeline.exec();
        }
      } while (cursor !== '0');
    } catch {
      /* Redis fallback */
    }
  }

  private mapJoinedTransactionRow(row: any) {
    const creatorId = Number(row.created_by_user_id ?? row.user_id);
    const createdBy =
      row.created_by_username
        ? {
            id: creatorId,
            username: row.created_by_username,
          }
        : null;

    const updatedBy =
      row.updated_by_user_id && row.updated_by_username
        ? {
            id: Number(row.updated_by_user_id),
            username: row.updated_by_username,
          }
        : null;

    return this.mapTransactionRow(
      row,
      {
        id: Number(row.category_id),
        name: row.category_name,
        icon: row.category_icon,
        color: row.category_color,
      },
      {
        id: Number(row.account_id),
        name: row.account_name,
        type: row.account_type,
        icon: row.account_icon,
        color: row.account_color,
      },
      createdBy,
      updatedBy
    );
  }

  private mapTransactionRow(row: any, category?: any, account?: any, createdBy?: any, updatedBy?: any) {
    const resolvedCreatedByUserId = row.created_by_user_id
      ? Number(row.created_by_user_id)
      : Number(row.user_id);

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
      notes: row.notes ?? null,
      date: Number(row.date),
      has_time: Boolean(row.has_time),
      status: row.status,
      is_installment: Boolean(row.is_installment),
      installment_number: row.installment_number ? Number(row.installment_number) : null,
      total_installments: row.total_installments ? Number(row.total_installments) : null,
      installment_group_id: row.installment_group_id || null,
      is_modified: Boolean(row.is_modified),
      modified_at: row.modified_at ? Number(row.modified_at) : null,
      created_by_user_id: resolvedCreatedByUserId,
      created_by: createdBy ?? null,
      updated_by_user_id: row.updated_by_user_id ? Number(row.updated_by_user_id) : null,
      updated_by: updatedBy ?? null,
      created_at: Number(row.created_at),
      updated_at: Number(row.updated_at),
    };
  }
}

