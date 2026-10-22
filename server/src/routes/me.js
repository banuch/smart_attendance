import { Router } from 'express';
import { z } from 'zod';

import { requireActive } from '../auth.js';
import { conflict } from '../errors.js';
import { toSqlTime } from '../lib/dates.js';
import { loadUserJson } from '../queries.js';
import { jsonField, photoUpload, requireJpeg } from '../upload.js';

const deviceBody = z.object({
  deviceId: z.string().trim().min(8).max(100),
  deviceModel: z.string().trim().max(100).default(''),
});

export const embeddingSchema = z.array(z.number().finite()).min(64).max(1024);

export function meRoutes({ pool, files }) {
  const router = Router();

  // Allowed while deactivated so the app can show the right screen.
  router.get('/', async (req, res) => {
    res.json(await loadUserJson(pool, req.user.id, files, req));
  });

  /** Binds the account to this phone on first login. */
  router.post('/device', requireActive, async (req, res) => {
    const { deviceId, deviceModel } = deviceBody.parse(req.body);
    const [result] = await pool.query(
      `UPDATE users SET device_id = ?, device_model = ?, device_bound_at = ?
       WHERE id = ? AND device_id IS NULL`,
      [deviceId, deviceModel, toSqlTime(new Date()), req.user.id],
    );
    if (result.affectedRows === 0) {
      throw conflict('This account is already registered to a phone. Ask your admin to reset it.');
    }
    res.json(await loadUserJson(pool, req.user.id, files, req));
  });

  /** Enrolls the reference face once; the admin can reset it. */
  router.post('/face', requireActive, photoUpload, async (req, res) => {
    const jpeg = requireJpeg(req);
    const embedding = embeddingSchema.parse(jsonField(req.body.embedding, 'embedding'));
    if (req.user.face_embedding != null) throw conflict('Your face is already registered.');

    const rel = await files.saveJpeg(`faces/${req.user.id}/${Date.now()}.jpg`, jpeg);
    const [result] = await pool.query(
      `UPDATE users SET face_embedding = ?, face_path = ?, face_enrolled_at = ?
       WHERE id = ? AND face_embedding IS NULL`,
      [JSON.stringify(embedding), rel, toSqlTime(new Date()), req.user.id],
    );
    if (result.affectedRows === 0) {
      await files.remove(rel);
      throw conflict('Your face is already registered.');
    }
    res.json(await loadUserJson(pool, req.user.id, files, req));
  });

  return router;
}
