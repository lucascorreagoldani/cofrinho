import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { dbPool } from './postgres.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function initializeDatabase(): Promise<void> {
  console.log('🔄 Executando migração do esquema PostgreSQL...');
  try {
    const candidates = [
      path.join(__dirname, 'schema.sql'),
      path.join(__dirname, 'database', 'schema.sql'),
      path.join(process.cwd(), 'dist', 'database', 'schema.sql'),
      path.join(process.cwd(), 'src', 'database', 'schema.sql'),
      path.join(process.cwd(), 'backend', 'src', 'database', 'schema.sql'),
    ];

    const schemaPath = candidates.find((p) => fs.existsSync(p));
    if (!schemaPath) {
      console.warn('⚠️ Arquivo schema.sql não localizado nos caminhos padrão. Prosseguindo sem migração.');
      return;
    }

    const sql = fs.readFileSync(schemaPath, 'utf-8');

    const client = await dbPool.connect();
    try {
      await client.query(sql);
      console.log('✅ Esquema do PostgreSQL sincronizado com sucesso!');
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('⚠️ Falha ao inicializar banco de dados no startup:', (error as Error).message);
  }
}

/* Executa direto apenas se invocado explicitamente como script CLI de inicialização */
if (process.argv[1] && (process.argv[1].endsWith('init.ts') || process.argv[1].endsWith('init.js'))) {
  initializeDatabase()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
}
