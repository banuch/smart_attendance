// Creates the first admin account (or resets an existing user to admin).
//
//   npm run create-admin -- --email you@example.com --name "Your Name"
//
// The password is asked for interactively, or read from ADMIN_PASSWORD.
import crypto from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { parseArgs } from 'node:util';

import bcrypt from 'bcryptjs';

import { loadConfig } from '../config.js';
import { createPool } from '../db.js';

const { values } = parseArgs({
  options: { email: { type: 'string' }, name: { type: 'string' } },
});
const email = values.email?.trim().toLowerCase();
if (!email || !email.includes('@')) {
  console.error('Usage: npm run create-admin -- --email you@example.com --name "Your Name"');
  process.exit(1);
}

let password = process.env.ADMIN_PASSWORD;
if (!password) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  password = await rl.question('Password (min 8 characters): ');
  rl.close();
}
if (!password || password.length < 8) {
  console.error('Password must be at least 8 characters.');
  process.exit(1);
}

const pool = createPool(loadConfig().db);
try {
  const hash = await bcrypt.hash(password, 12);
  const [existing] = await pool.query('SELECT id FROM users WHERE email = ?', [email]);
  if (existing[0]) {
    await pool.query(
      `UPDATE users SET role = 'admin', active = TRUE, password_hash = ?,
         token_version = token_version + 1 WHERE id = ?`,
      [hash, existing[0].id],
    );
    console.log(`Updated ${email}: admin, active, new password.`);
  } else {
    await pool.query(
      `INSERT INTO users (id, name, email, password_hash, role, active)
       VALUES (?, ?, ?, ?, 'admin', TRUE)`,
      [crypto.randomUUID(), values.name?.trim() || email, email, hash],
    );
    console.log(`Created admin ${email}.`);
  }
} finally {
  await pool.end();
}
