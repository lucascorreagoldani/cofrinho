import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { dbPool } from './postgres.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function initializeDatabase() {
  console.log('🔄 Executando migração do esquema PostgreSQL...');
  try {
    const schemaPath = path.join(__dirname, 'schema.sql');
    const sql = fs.readFileSync(schemaPath, 'utf-8');

    const client = await dbPool.connect();
    try {
      await client.query(sql);
      console.log('✅ Esquema do PostgreSQL inicializado com sucesso! (users, users_sessions, users_preferences)');
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('❌ Falha ao inicializar banco de dados:', (error as Error).message);
    throw error;
  }
}

/* Executa direto se chamado via CLI */
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  initializeDatabase()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
}

