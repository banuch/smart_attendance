import bcrypt from 'bcryptjs';
import { Router } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';

import { signToken } from '../auth.js';
import { HttpError, forbidden } from '../errors.js';
import { loadUserJson } from '../queries.js';

const loginBody = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1).max(200),
});

// Compared against when the email is unknown, so timing doesn't reveal it.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', 10);

export function authRoutes({ pool, config, files }) {
  const router = Router();

  router.post(
    '/login',
    rateLimit({
      windowMs: 15 * 60 * 1000,
      limit: 20,
      standardHeaders: 'draft-8',
      legacyHeaders: false,
      message: { error: 'Too many attempts. Try again later.' },
    }),
    async (req, res) => {
      const { email, password } = loginBody.parse(req.body);
      const [rows] = await pool.query('SELECT * FROM users WHERE email = ?', [email]);
      const user = rows[0];
      const ok = await bcrypt.compare(password, user?.password_hash ?? DUMMY_HASH);
      if (!user || !ok) throw new HttpError(401, 'Incorrect email or password.');
      if (!user.active) throw forbidden('This account has been deactivated.');
      res.json({
        token: signToken(user, config),
        user: await loadUserJson(pool, user.id, files, req),
      });
    },
  );

  return router;
}
