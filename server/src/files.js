import crypto from 'node:crypto';
import { mkdir, writeFile, unlink } from 'node:fs/promises';
import path from 'node:path';

// Links stay identical for a whole window so image caches keep working,
// and are valid for at least one more window after that.
const WINDOW_SECONDS = 3 * 60 * 60;

export function createFileStore({ uploadDir, jwtSecret, publicUrl }) {
  const root = path.resolve(uploadDir);
  const key = crypto.createHash('sha256').update(`files:${jwtSecret}`).digest();
  const sign = (rel, exp) =>
    crypto.createHmac('sha256', key).update(`${rel}\n${exp}`).digest('base64url');

  function resolveInside(rel) {
    const full = path.resolve(root, rel);
    if (!full.startsWith(root + path.sep)) throw new Error('Path escapes upload dir');
    return full;
  }

  return {
    root,

    /** Saves a JPEG and returns its relative path. */
    async saveJpeg(rel, buffer) {
      const full = resolveInside(rel);
      await mkdir(path.dirname(full), { recursive: true });
      await writeFile(full, buffer, { flag: 'wx' });
      return rel;
    },

    async remove(rel) {
      await unlink(resolveInside(rel)).catch(() => {});
    },

    /** Absolute, signed, expiring URL for [rel]; null when [rel] is empty. */
    url(rel, req) {
      if (!rel) return null;
      const now = Math.floor(Date.now() / 1000);
      const exp = (Math.floor(now / WINDOW_SECONDS) + 2) * WINDOW_SECONDS;
      const base = publicUrl || `${req.protocol}://${req.get('host')}`;
      const encoded = rel.split('/').map(encodeURIComponent).join('/');
      return `${base}/files/${encoded}?exp=${exp}&sig=${sign(rel, exp)}`;
    },

    /** Absolute file path when the signature is valid and unexpired, else null. */
    verify(rel, exp, sig) {
      const expNum = Number(exp);
      if (!Number.isInteger(expNum) || expNum < Date.now() / 1000 || typeof sig !== 'string') {
        return null;
      }
      const expected = Buffer.from(sign(rel, expNum));
      const given = Buffer.from(sig);
      if (expected.length !== given.length || !crypto.timingSafeEqual(expected, given)) {
        return null;
      }
      try {
        return resolveInside(rel);
      } catch {
        return null;
      }
    },
  };
}

export const isJpeg = (buf) =>
  buf?.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
