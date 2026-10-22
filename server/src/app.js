import cors from 'cors';
import express from 'express';
import helmet from 'helmet';

import { authenticate, requireAdmin } from './auth.js';
import { errorHandler, notFound } from './errors.js';
import { createFileStore } from './files.js';
import { attendanceRoutes } from './routes/attendance.js';
import { authRoutes } from './routes/auth.js';
import { shiftRoutes, siteRoutes } from './routes/catalog.js';
import { meRoutes } from './routes/me.js';
import { userRoutes } from './routes/users.js';

/** Allows the configured origins plus any localhost port (Flutter web dev). */
function corsOptions(origins) {
  return {
    origin(origin, cb) {
      const local = origin && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
      cb(null, !origin || local || origins.includes(origin));
    },
    maxAge: 600,
  };
}

export function createApp({ pool, config }) {
  const files = createFileStore(config);
  const ctx = { pool, config, files };
  const app = express();

  app.set('trust proxy', 1); // behind nginx
  app.disable('x-powered-by');
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors(corsOptions(config.corsOrigins)));
  app.use(express.json({ limit: '100kb' }));

  app.get('/api/health', async (req, res) => {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  });

  app.use('/api/auth', authRoutes(ctx));

  const auth = authenticate(ctx);
  app.use('/api/me', auth, meRoutes(ctx));
  app.use('/api/users', auth, requireAdmin, userRoutes(ctx));
  app.use('/api/sites', auth, siteRoutes(ctx));
  app.use('/api/shifts', auth, shiftRoutes(ctx));
  app.use('/api/attendance', auth, attendanceRoutes(ctx));

  // Photos: access is granted by the signed link the API handed out.
  app.get('/files/*path', (req, res, next) => {
    const rel = req.params.path.join('/');
    const full = files.verify(rel, req.query.exp, req.query.sig);
    if (!full) return next(notFound('Link expired or invalid.'));
    res.sendFile(full, { maxAge: '3h', headers: { 'Cache-Control': 'private, max-age=10800' } }, (err) => {
      if (err && !res.headersSent) next(notFound());
    });
  });

  app.use((req, res, next) => next(notFound()));
  app.use(errorHandler);
  return app;
}
