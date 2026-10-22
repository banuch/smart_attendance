import jwt from 'jsonwebtoken';

import { HttpError, forbidden } from './errors.js';

export function signToken(user, config) {
  return jwt.sign({ tv: user.token_version }, config.jwtSecret, {
    subject: user.id,
    expiresIn: config.tokenTtl,
    algorithm: 'HS256',
  });
}

/** Loads the signed-in user into req.user, or answers 401. */
export function authenticate({ pool, config }) {
  return async (req, res, next) => {
    const header = req.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) return next(new HttpError(401, 'Sign in required.'));
    let claims;
    try {
      claims = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
    } catch {
      return next(new HttpError(401, 'Session expired. Sign in again.'));
    }
    const [rows] = await pool.query('SELECT * FROM users WHERE id = ?', [claims.sub]);
    const user = rows[0];
    if (!user || user.token_version !== claims.tv) {
      return next(new HttpError(401, 'Session expired. Sign in again.'));
    }
    user.active = !!user.active;
    req.user = user;
    next();
  };
}

export function requireActive(req, res, next) {
  if (!req.user.active) return next(forbidden('Your account has been deactivated.'));
  next();
}

export function requireAdmin(req, res, next) {
  if (!req.user.active || req.user.role !== 'admin') return next(forbidden('Admin access required.'));
  next();
}
