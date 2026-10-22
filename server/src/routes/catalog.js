import crypto from 'node:crypto';

import { Router } from 'express';
import { z } from 'zod';

import { requireAdmin } from '../auth.js';
import { notFound } from '../errors.js';
import { shiftJson, siteJson } from '../queries.js';

const siteBody = z.object({
  name: z.string().trim().min(1).max(100),
  address: z.string().trim().max(255).default(''),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  radiusMeters: z.number().min(10).max(5000),
});

const hm = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use HH:mm');
const minutes = z.number().int().min(0).max(24 * 60);

const shiftBody = z.object({
  name: z.string().trim().min(1).max(100),
  start: hm,
  end: hm,
  graceMinutes: minutes.default(10),
  halfDayAfterMinutes: minutes.default(120),
  minFullDayMinutes: minutes.default(360),
  workDays: z.array(z.number().int().min(1).max(7)).max(7).default([1, 2, 3, 4, 5, 6]),
});

/**
 * Read for every signed-in user, write for admins. [values] maps the parsed
 * body to the table's [columns], in order.
 */
function crud({ pool, table, label, schema, toJson, columns, values: toValues }) {
  const router = Router();
  const load = async (id) => {
    const [rows] = await pool.query(`SELECT * FROM ${table} WHERE id = ?`, [id]);
    if (!rows[0]) throw notFound(`${label} not found.`);
    return toJson(rows[0]);
  };

  router.get('/', async (req, res) => {
    const [rows] = await pool.query(`SELECT * FROM ${table} ORDER BY name`);
    res.json(rows.map(toJson));
  });

  router.post('/', requireAdmin, async (req, res) => {
    const id = crypto.randomUUID();
    const values = toValues(schema.parse(req.body));
    await pool.query(
      `INSERT INTO ${table} (id, ${columns.join(', ')}) VALUES (?${', ?'.repeat(columns.length)})`,
      [id, ...values],
    );
    res.status(201).json(await load(id));
  });

  router.put('/:id', requireAdmin, async (req, res) => {
    const values = toValues(schema.parse(req.body));
    const [result] = await pool.query(
      `UPDATE ${table} SET ${columns.map((n) => `${n} = ?`).join(', ')} WHERE id = ?`,
      [...values, req.params.id],
    );
    if (result.affectedRows === 0) throw notFound(`${label} not found.`);
    res.json(await load(req.params.id));
  });

  router.delete('/:id', requireAdmin, async (req, res) => {
    const [result] = await pool.query(`DELETE FROM ${table} WHERE id = ?`, [req.params.id]);
    if (result.affectedRows === 0) throw notFound(`${label} not found.`);
    res.status(204).end();
  });

  return router;
}

export const siteRoutes = ({ pool }) =>
  crud({
    pool,
    table: 'sites',
    label: 'Site',
    schema: siteBody,
    toJson: siteJson,
    columns: ['name', 'address', 'lat', 'lng', 'radius_meters'],
    values: (b) => [b.name, b.address, b.lat, b.lng, b.radiusMeters],
  });

export const shiftRoutes = ({ pool }) =>
  crud({
    pool,
    table: 'shifts',
    label: 'Shift',
    schema: shiftBody,
    toJson: shiftJson,
    columns: [
      'name', 'start_time', 'end_time', 'grace_minutes',
      'half_day_after_minutes', 'min_full_day_minutes', 'work_days',
    ],
    values: (b) => [
      b.name, b.start, b.end, b.graceMinutes,
      b.halfDayAfterMinutes, b.minFullDayMinutes,
      JSON.stringify([...new Set(b.workDays)].sort()),
    ],
  });
