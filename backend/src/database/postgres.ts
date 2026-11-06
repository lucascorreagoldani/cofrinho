import pg from 'pg';
import { env } from '../config/env.js';

const { Pool } = pg;

export const dbPool = new Pool({
  connectionString: env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

dbPool.on('error', (err) => {
  console.error('⚠️ Erro inesperado no pool do PostgreSQL:', err.message);
});

export async function checkDatabaseConnection(): Promise<boolean> {
  try {
    const client = await dbPool.connect();
    await client.query('SELECT 1');
    client.release();
    return true;
  } catch (error) {
    console.warn('⚠️ Não foi possível conectar ao PostgreSQL. Verifique se o banco está ativo:', (error as Error).message);
    return false;
  }
}

