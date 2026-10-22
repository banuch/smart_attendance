import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mysql from 'mysql2/promise';

import { loadConfig } from './config.js';

const sqlDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'sql');

/** Applies every sql/NNN_*.sql file that has not been applied yet, in order. */
export async function migrate(db, log = console.log) {
  const conn = await mysql.createConnection({ ...db, multipleStatements: true });
  try {
    await conn.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      name VARCHAR(255) NOT NULL PRIMARY KEY,
      applied_at DATETIME(3) NOT NULL DEFAULT (UTC_TIMESTAMP(3))
    )`);
    const [rows] = await conn.query('SELECT name FROM schema_migrations');
    const applied = new Set(rows.map((r) => r.name));
    const files = (await readdir(sqlDir)).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      if (applied.has(file)) continue;
      log(`Applying ${file}`);
      await conn.query(await readFile(path.join(sqlDir, file), 'utf8'));
      await conn.query('INSERT INTO schema_migrations (name) VALUES (?)', [file]);
    }
  } finally {
    await conn.end();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await migrate(loadConfig().db);
  console.log('Database is up to date');
}
