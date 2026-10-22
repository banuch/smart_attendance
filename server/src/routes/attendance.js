import { Router } from 'express';
import { z } from 'zod';

import { requireActive, requireAdmin } from '../auth.js';
import { transaction } from '../db.js';
import { HttpError, badRequest, conflict, forbidden, notFound } from '../errors.js';
import { dateKey, toSqlTime } from '../lib/dates.js';
import { nearestSite } from '../lib/geo.js';
import { afterCheckOut, evaluatePunch } from '../lib/punch_rules.js';
import { ATTENDANCE_SELECT, attendanceJson, loadAttendance, siteJson } from '../queries.js';
import { jsonField, photoUpload, requireJpeg } from '../upload.js';
import { embeddingSchema } from './me.js';

const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use yyyy-MM-dd');

const rangeQuery = z
  .object({ from: day, to: day, uid: z.string().uuid().optional() })
  .refine((q) => q.from <= q.to, 'from must not be after to');

const punchBody = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  accuracy: z.coerce.number().min(0).max(100000),
  mocked: z.enum(['true', 'false']).default('false'),
  deviceId: z.string().min(1).max(100),
});

const reviewBody = z.object({
  decision: z.enum(['approved', 'rejected']),
  note: z.string().trim().max(500).nullable().optional(),
});

export function attendanceRoutes({ pool, config, files }) {
  const router = Router();
  router.use(requireActive);

  const list = (rows, req) => rows.map((r) => attendanceJson(r, files, req));

  /** Records in a date range. Employees only ever get their own. */
  router.get('/', async (req, res) => {
    const q = rangeQuery.parse(req.query);
    const uid = req.user.role === 'admin' ? q.uid : req.user.id;
    const params = [q.from, q.to];
    let sql = `${ATTENDANCE_SELECT} WHERE a.date BETWEEN ? AND ?`;
    if (uid) {
      sql += ' AND a.user_id = ?';
      params.push(uid);
    }
    const [rows] = await pool.query(`${sql} ORDER BY a.date DESC, a.employee_name`, params);
    res.json(list(rows, req));
  });

  /** The signed-in user's record for today (server calendar day). */
  router.get('/today', async (req, res) => {
    const date = dateKey(new Date(), config.timezone);
    const record = await loadAttendance(pool, `${req.user.id}_${date}`, files, req);
    res.json({ date, record });
  });

  router.get('/pending', requireAdmin, async (req, res) => {
    const [rows] = await pool.query(
      `${ATTENDANCE_SELECT} WHERE a.flagged = TRUE AND a.reviewed = FALSE ORDER BY a.date DESC`,
    );
    res.json(list(rows, req));
  });

  /**
   * Check-in (first punch of the day) or check-out (second). Everything that
   * decides whether the punch counts is checked here, not trusted from the
   * phone: time, day, device, geofence, write-once and the face match.
   */
  router.post('/punch', photoUpload, async (req, res) => {
    const body = punchBody.parse(req.body);
    const embedding = req.body.embedding
      ? embeddingSchema.parse(jsonField(req.body.embedding, 'embedding'))
      : null;
    const jpeg = requireJpeg(req);
    const user = req.user;

    if (!user.device_id || user.device_id !== body.deviceId) {
      throw forbidden('This phone is not registered to your account.');
    }
    if (body.mocked === 'true') {
      throw badRequest('Fake GPS detected. Disable mock location apps and try again.');
    }

    const [assigned] = await pool.query(
      `SELECT s.* FROM sites s
       WHERE NOT EXISTS (SELECT 1 FROM user_sites WHERE user_id = ?)
          OR s.id IN (SELECT site_id FROM user_sites WHERE user_id = ?)`,
      [user.id, user.id],
    );
    const match = nearestSite(body.lat, body.lng, assigned.map(siteJson));
    if (!match) throw new HttpError(422, 'No work site is configured for you. Contact your admin.');
    if (!match.inside) {
      throw new HttpError(
        422,
        `You are ${Math.round(match.distance)} m from ${match.site.name}. ` +
          `Move within ${Math.round(match.site.radiusMeters)} m to punch.`,
      );
    }

    const { faceScore, reasons } = evaluatePunch(
      { embedding, enrolledEmbedding: user.face_embedding, accuracy: body.accuracy },
      config,
    );

    const now = new Date();
    const date = dateKey(now, config.timezone);
    const id = `${user.id}_${date}`;

    const [existing] = await pool.query(
      `SELECT a.flagged, a.reviewed, p.kind FROM attendance a
       LEFT JOIN punches p ON p.attendance_id = a.id AND p.kind = 'out'
       WHERE a.id = ?`,
      [id],
    );
    if (existing[0]?.kind === 'out') throw conflict('You have already checked out today.');
    const kind = existing[0] ? 'out' : 'in';

    const photoPath = await files.saveJpeg(
      `selfies/${user.id}/${date}_${kind}_${now.getTime()}.jpg`,
      jpeg,
    );
    const punchValues = [
      id, kind, toSqlTime(now), body.lat, body.lng, body.accuracy, match.site.id,
      match.site.name, match.distance, photoPath, faceScore, JSON.stringify(reasons), body.deviceId,
    ];

    try {
      await transaction(pool, async (conn) => {
        if (kind === 'in') {
          await conn.query(
            `INSERT INTO attendance (id, user_id, employee_name, date, shift_id, flagged, reviewed)
             VALUES (?, ?, ?, ?, ?, ?, FALSE)`,
            [id, user.id, user.name, date, user.shift_id, reasons.length > 0],
          );
        } else {
          // Lock the row so two simultaneous check-outs can't both pass.
          const [[record]] = await conn.query(
            'SELECT flagged, reviewed FROM attendance WHERE id = ? FOR UPDATE',
            [id],
          );
          const next = afterCheckOut(
            { flagged: !!record.flagged, reviewed: !!record.reviewed },
            reasons,
          );
          await conn.query('UPDATE attendance SET flagged = ?, reviewed = ? WHERE id = ?', [
            next.flagged, next.reviewed, id,
          ]);
        }
        await conn.query(
          `INSERT INTO punches (attendance_id, kind, time, lat, lng, accuracy, site_id, site_name,
             distance_meters, photo_path, face_score, flag_reasons, device_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          punchValues,
        );
      });
    } catch (e) {
      await files.remove(photoPath);
      if (e.code === 'ER_DUP_ENTRY') {
        throw conflict(kind === 'in' ? 'You have already checked in today.' : 'You have already checked out today.');
      }
      throw e;
    }

    res.status(201).json({ kind, record: await loadAttendance(pool, id, files, req) });
  });

  router.post('/:id/review', requireAdmin, async (req, res) => {
    const { decision, note } = reviewBody.parse(req.body);
    const [result] = await pool.query(
      `UPDATE attendance SET reviewed = TRUE, review_decision = ?, reviewed_by = ?,
         reviewed_at = ?, review_note = ?
       WHERE id = ?`,
      [decision, req.user.id, toSqlTime(new Date()), note || null, req.params.id],
    );
    if (result.affectedRows === 0) throw notFound('Attendance record not found.');
    res.json(await loadAttendance(pool, req.params.id, files, req));
  });

  return router;
}
