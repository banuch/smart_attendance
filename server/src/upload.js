import multer from 'multer';

import { badRequest } from './errors.js';
import { isJpeg } from './files.js';

/** Accepts a single JPEG in the `photo` field, kept in memory. */
export const photoUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1, fields: 20 },
}).single('photo');

export function requireJpeg(req) {
  if (!req.file || !isJpeg(req.file.buffer)) throw badRequest('A JPEG photo is required.');
  return req.file.buffer;
}

/** Parses a JSON-encoded multipart field. */
export function jsonField(value, name) {
  if (value == null || value === '') return null;
  try {
    return JSON.parse(value);
  } catch {
    throw badRequest(`${name} must be JSON.`);
  }
}
