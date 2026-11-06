import { dbPool } from '../../database/postgres.js';
import { redis } from '../../database/redis.js';
import { ConflictError, NotFoundError } from '../../shared/errors/AppError.js';
import { CANONICAL_CATEGORIES } from '../../shared/constants/defaults.js';
import { z } from 'zod';
import {
  categoryResponseSchema,
  createCategoryBodySchema,
  updateCategoryBodySchema,
} from './categories.schemas.js';

export class CategoriesService {
  private getCacheKey(userId: number): string {
    return `cofrinho:user:${userId}:categories`;
  }

  async listCategories(
    userId: number,
    includeHidden = false
  ): Promise<z.infer<typeof categoryResponseSchema>[]> {
    const cacheKey = this.getCacheKey(userId);

    /* 1. Tenta recuperar do cache Redis caso não inclua ocultos */
    if (!includeHidden) {
      try {
        const cached = await redis.get(cacheKey);
        if (cached) {
          return JSON.parse(cached);
        }
      } catch {
        /* Fallback silencioso para o banco caso o Redis oscile */
      }
    }

    /* 2. Consulta no PostgreSQL com índices otimizados */
    const statuses = includeHidden ? ['active', 'hidden'] : ['active'];
    const result = await dbPool.query(
      `SELECT id, user_id, name, icon, color, is_default, status, created_at, updated_at
       FROM categories
       WHERE user_id = $1 AND status = ANY($2::varchar[])
       ORDER BY is_default DESC, name ASC`,
      [userId, statuses]
    );

    /* 3. Se o usuário ainda não tiver categorias cadastradas, faz o seed canônico */
    if (result.rows.length === 0) {
      await this.seedCanonicalCategories(userId);
      return this.listCategories(userId, includeHidden);
    }

    const categories = result.rows.map((row) => ({
      id: Number(row.id),
      user_id: Number(row.user_id),
      name: row.name,
      icon: row.icon,
      color: row.color,
      is_default: Boolean(row.is_default),
      status: row.status,
      created_at: Number(row.created_at),
      updated_at: Number(row.updated_at),
    }));

    /* 4. Grava no cache Redis com TTL de 1 hora se não incluir ocultos */
    if (!includeHidden) {
      try {
        await redis.set(cacheKey, JSON.stringify(categories), 'EX', 3600);
      } catch {
        /* Redis fallback */
      }
    }

    return categories;
  }

  async createCategory(userId: number, data: z.infer<typeof createCategoryBodySchema>) {
    const nowTimestamp = Date.now();

    /* 1. Verifica se já existe categoria com o mesmo nome para este usuário */
    const existing = await dbPool.query(
      `SELECT id, status FROM categories WHERE user_id = $1 AND LOWER(name) = LOWER($2)`,
      [userId, data.name]
    );

    if (existing.rows.length > 0) {
      if (existing.rows[0].status === 'deleted') {
        /* Reativa categoria previamente excluída */
        const updated = await dbPool.query(
          `UPDATE categories
           SET status = 'active', icon = $1, color = $2, updated_at = $3
           WHERE id = $4
           RETURNING id, user_id, name, icon, color, is_default, status, created_at, updated_at`,
          [data.icon, data.color, nowTimestamp, existing.rows[0].id]
        );
        await this.invalidateCache(userId);
        return this.mapCategoryRow(updated.rows[0]);
      }
      throw new ConflictError(`Já existe uma categoria chamada "${data.name}".`);
    }

    /* 2. Insere categoria */
    const result = await dbPool.query(
      `INSERT INTO categories (user_id, name, icon, color, is_default, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, false, 'active', $5, $5)
       RETURNING id, user_id, name, icon, color, is_default, status, created_at, updated_at`,
      [userId, data.name, data.icon, data.color, nowTimestamp]
    );

    await this.invalidateCache(userId);
    return this.mapCategoryRow(result.rows[0]);
  }

  async updateCategory(userId: number, categoryId: number, data: z.infer<typeof updateCategoryBodySchema>) {
    const nowTimestamp = Date.now();

    const existing = await dbPool.query(
      `SELECT id, name FROM categories WHERE id = $1 AND user_id = $2`,
      [categoryId, userId]
    );

    if (existing.rows.length === 0) {
      throw new NotFoundError('Categoria não encontrada ou não pertence a este usuário.');
    }

    /* Valida conflito de nome se estiver alterando o nome */
    if (data.name && data.name.toLowerCase() !== existing.rows[0].name.toLowerCase()) {
      const conflict = await dbPool.query(
        `SELECT id FROM categories WHERE user_id = $1 AND LOWER(name) = LOWER($2) AND id != $3`,
        [userId, data.name, categoryId]
      );
      if (conflict.rows.length > 0) {
        throw new ConflictError(`Já existe uma categoria chamada "${data.name}".`);
      }
    }

    const fields: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (data.name !== undefined) {
      fields.push(`name = $${idx++}`);
      values.push(data.name);
    }
    if (data.icon !== undefined) {
      fields.push(`icon = $${idx++}`);
      values.push(data.icon);
    }
    if (data.color !== undefined) {
      fields.push(`color = $${idx++}`);
      values.push(data.color);
    }
    if (data.status !== undefined) {
      fields.push(`status = $${idx++}`);
      values.push(data.status);
    }

    fields.push(`updated_at = $${idx++}`);
    values.push(nowTimestamp);

    values.push(categoryId);
    values.push(userId);

    const query = `
      UPDATE categories
      SET ${fields.join(', ')}
      WHERE id = $${idx++} AND user_id = $${idx}
      RETURNING id, user_id, name, icon, color, is_default, status, created_at, updated_at
    `;

    const result = await dbPool.query(query, values);
    await this.invalidateCache(userId);

    return this.mapCategoryRow(result.rows[0]);
  }

  async deleteCategory(userId: number, categoryId: number) {
    const nowTimestamp = Date.now();

    /* Soft delete */
    const result = await dbPool.query(
      `UPDATE categories
       SET status = 'deleted', updated_at = $1
       WHERE id = $2 AND user_id = $3
       RETURNING id`,
      [nowTimestamp, categoryId, userId]
    );

    if (result.rows.length === 0) {
      throw new NotFoundError('Categoria não encontrada ou não pertence a este usuário.');
    }

    await this.invalidateCache(userId);
    return { success: true };
  }

  private async seedCanonicalCategories(userId: number): Promise<void> {
    const now = Date.now();
    for (const cat of CANONICAL_CATEGORIES) {
      await dbPool.query(
        `INSERT INTO categories (user_id, name, icon, color, is_default, status, created_at, updated_at)
         VALUES ($1, $2, $3, $4, true, 'active', $5, $5)
         ON CONFLICT (user_id, name) DO NOTHING`,
        [userId, cat.name, cat.icon, cat.color, now]
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

  private mapCategoryRow(row: any) {
    return {
      id: Number(row.id),
      user_id: Number(row.user_id),
      name: row.name,
      icon: row.icon,
      color: row.color,
      is_default: Boolean(row.is_default),
      status: row.status,
      created_at: Number(row.created_at),
      updated_at: Number(row.updated_at),
    };
  }
}
