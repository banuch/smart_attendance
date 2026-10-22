import mysql from 'mysql2/promise';

export function createPool(db) {
  return mysql.createPool({
    ...db,
    waitForConnections: true,
    connectionLimit: 10,
    // DATE / DATETIME come back as strings; every DATETIME column holds UTC.
    dateStrings: true,
    charset: 'utf8mb4',
  });
}

/** Runs [fn] inside a transaction on a dedicated connection. */
export async function transaction(pool, fn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (e) {
    await conn.rollback();
    throw e;
  } finally {
    conn.release();
  }
}
