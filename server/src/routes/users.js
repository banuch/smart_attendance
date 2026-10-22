import crypto from 'node:crypto';

import bcrypt from 'bcryptjs';
import { Router } from 'express';
import { z } from 'zod';

import { transaction } from '../db.js';
import { badRequest, conflict, notFound } from '../errors.js';
import { loadUserJson, siteIdsByUser, userJson } from '../queries.js';

const password = z.string().min(8, 'Password must be at least 8 characters.').max(200);

const profile = z.object({
  name: z.string().trim().min(1).max(100),
  email: z.string().trim().toLowerCase().email().max(190),
  phone: z.string().trim().max(30).default(''),
  employeeCode: z.string().trim().max(50).default(''),
  role: z.enum(['admin', 'employee']).default('employee'),
  active: z.boolean().default(true),
  siteIds: z.array(z.string().uuid()).max(500).default([]),
  shiftId: z.string().uuid().nullable().default(null),
});

const createBody = profile.extend({ password });

async function setSites(conn, userId, siteIds) {
  await conn.query('DELETE FROM user_sites WHERE user_id = ?', [userId]);
  const unique = [...new Set(siteIds)];
  if (unique.length) {
    await conn.query('INSERT INTO user_sites (user_id, site_id) VALUES ?', [
      unique.map((s) => [userId, s]),
    ]);
  }
}

function rethrowDuplicateEmail(e) {
  if (e.code === 'ER_DUP_ENTRY') throw conflict('An account with this email already exists.');
  throw e;
}

/** Admin-only management of employee and admin accounts. */
export function userRoutes({ pool, files }) {
  const router = Router();

  async function update(req, sql, params) {
    const [result] = await pool.query(sql, params);
    if (result.affectedRows === 0) throw notFound('Employee not found.');
    return loadUserJson(pool, req.params.id, files, req);
  }

  router.get('/', async (req, res) => {
    const [rows] = await pool.query('SELECT * FROM users ORDER BY name');
    const sites = await siteIdsByUser(pool, rows.map((r) => r.id));
    res.json(rows.map((r) => userJson(r, sites.get(r.id), files, req)));
  });

  router.post('/', async (req, res) => {
    const body = createBody.parse(req.body);
    const id = crypto.randomUUID();
    const hash = await bcrypt.hash(body.password, 12);
    await transaction(pool, async (conn) => {
      await conn.query(
        `INSERT INTO users (id, name, email, password_hash, phone, employee_code, role, active, shift_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [id, body.name, body.email, hash, body.phone, body.employeeCode, body.role, body.active, body.shiftId],
      );
      await setSites(conn, id, body.siteIds);
    }).catch(rethrowDuplicateEmail);
    res.status(201).json(await loadUserJson(pool, id, files, req));
  });

  router.put('/:id', async (req, res) => {
    const body = profile.parse(req.body);
    const { id } = req.params;
    if (id === req.user.id && (body.role !== 'admin' || !body.active)) {
      throw badRequest('You cannot remove your own admin access.');
    }
    const found = await transaction(pool, async (conn) => {
      const [result] = await conn.query(
        `UPDATE users SET name = ?, email = ?, phone = ?, employee_code = ?, role = ?, active = ?, shift_id = ?
         WHERE id = ?`,
        [body.name, body.email, body.phone, body.employeeCode, body.role, body.active, body.shiftId, id],
      );
      if (result.affectedRows === 0) return false;
      await setSites(conn, id, body.siteIds);
      return true;
    }).catch(rethrowDuplicateEmail);
    if (!found) throw notFound('Employee not found.');
    res.json(await loadUserJson(pool, id, files, req));
  });

  router.post('/:id/reset-device', async (req, res) => {
    res.json(await update(
      req,
      'UPDATE users SET device_id = NULL, device_model = NULL, device_bound_at = NULL WHERE id = ?',
      [req.params.id],
    ));
  });

  router.post('/:id/reset-face', async (req, res) => {
    res.json(await update(
      req,
      'UPDATE users SET face_embedding = NULL, face_path = NULL, face_enrolled_at = NULL WHERE id = ?',
      [req.params.id],
    ));
  });

  /** Sets a new password and signs the user out everywhere. */
  router.post('/:id/password', async (req, res) => {
    const hash = await bcrypt.hash(z.object({ password }).parse(req.body).password, 12);
    res.json(await update(
      req,
      'UPDATE users SET password_hash = ?, token_version = token_version + 1 WHERE id = ?',
      [hash, req.params.id],
    ));
  });

  return router;
}
