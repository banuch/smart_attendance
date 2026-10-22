import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import { createFileStore, isJpeg } from '../src/files.js';
import { dateKey, fromSqlTime, toSqlTime } from '../src/lib/dates.js';
import { cosineSimilarity } from '../src/lib/face.js';
import { distanceMeters, nearestSite } from '../src/lib/geo.js';
import { FlagReason, afterCheckOut, evaluatePunch } from '../src/lib/punch_rules.js';

const config = { faceMatchThreshold: 0.55, maxGpsAccuracyMeters: 50 };

test('distance: one degree of latitude is about 111 km', () => {
  const d = distanceMeters(12, 77, 13, 77);
  assert.ok(Math.abs(d - 111195) < 100, `got ${d}`);
});

test('nearestSite prefers a site the point is inside of', () => {
  const big = { id: 'big', lat: 12.0, lng: 77.0, radiusMeters: 1000 };
  const near = { id: 'near', lat: 12.0045, lng: 77.0, radiusMeters: 50 };
  // The point is ~55 m from "near" (outside it) and ~445 m from "big" (inside).
  const onlyNear = nearestSite(12.004, 77.0, [near]);
  assert.equal(onlyNear.inside, false);
  assert.ok(Math.abs(onlyNear.distance - 55.6) < 1);
  const both = nearestSite(12.004, 77.0, [near, big]);
  assert.equal(both.site.id, 'big', 'inside beats nearer-but-outside');
  assert.equal(both.inside, true);
  assert.equal(nearestSite(0, 0, []), null);
});

test('cosine similarity', () => {
  assert.equal(cosineSimilarity([1, 0], [1, 0]), 1);
  assert.equal(cosineSimilarity([1, 0], [0, 1]), 0);
  assert.equal(cosineSimilarity([1, 0], [1, 0, 0]), 0);
  assert.equal(cosineSimilarity([], []), 0);
});

test('dateKey uses the configured time zone', () => {
  const t = new Date('2026-10-21T20:00:00Z');
  assert.equal(dateKey(t, 'UTC'), '2026-10-21');
  assert.equal(dateKey(t, 'Asia/Kolkata'), '2026-10-22'); // 01:30 next day
  assert.equal(dateKey(t, 'America/New_York'), '2026-10-21');
});

test('SQL time round trip keeps milliseconds and UTC', () => {
  const t = new Date('2026-10-21T08:05:03.123Z');
  assert.equal(toSqlTime(t), '2026-10-21 08:05:03.123');
  assert.equal(fromSqlTime(toSqlTime(t)), t.toISOString());
  assert.equal(fromSqlTime(null), null);
});

test('evaluatePunch flags face mismatch, unverified face and weak GPS', () => {
  const a = [1, 0, 0];
  assert.deepEqual(
    evaluatePunch({ embedding: a, enrolledEmbedding: a, accuracy: 10 }, config),
    { faceScore: 1, reasons: [] },
  );
  const mismatch = evaluatePunch({ embedding: a, enrolledEmbedding: [0, 1, 0], accuracy: 10 }, config);
  assert.equal(mismatch.faceScore, 0);
  assert.deepEqual(mismatch.reasons, [FlagReason.faceMismatch]);
  assert.deepEqual(
    evaluatePunch({ embedding: null, enrolledEmbedding: a, accuracy: 80 }, config).reasons,
    [FlagReason.faceNotVerified, FlagReason.lowGpsAccuracy],
  );
  assert.deepEqual(
    evaluatePunch({ embedding: [1, 0], enrolledEmbedding: a, accuracy: 10 }, config).reasons,
    [FlagReason.faceNotVerified],
    'different model sizes are not compared',
  );
});

test('afterCheckOut: flags stick and a flagged check-out needs a new review', () => {
  assert.deepEqual(afterCheckOut({ flagged: false, reviewed: false }, []), { flagged: false, reviewed: false });
  assert.deepEqual(afterCheckOut({ flagged: true, reviewed: true }, []), { flagged: true, reviewed: true });
  assert.deepEqual(afterCheckOut({ flagged: true, reviewed: true }, ['x']), { flagged: true, reviewed: false });
  assert.deepEqual(afterCheckOut({ flagged: false, reviewed: false }, ['x']), { flagged: true, reviewed: false });
});

test('signed file links verify, and reject tampering, expiry and traversal', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'sa-files-'));
  const files = createFileStore({ uploadDir: dir, jwtSecret: 'x'.repeat(32), publicUrl: 'https://a.test' });
  const url = new URL(files.url('selfies/u1/a.jpg', null));
  assert.equal(url.origin, 'https://a.test');
  const exp = url.searchParams.get('exp');
  const sig = url.searchParams.get('sig');
  assert.equal(files.verify('selfies/u1/a.jpg', exp, sig), path.join(dir, 'selfies', 'u1', 'a.jpg'));
  assert.equal(files.verify('selfies/u2/a.jpg', exp, sig), null);
  assert.equal(files.verify('selfies/u1/a.jpg', String(Number(exp) + 1), sig), null);
  assert.equal(files.verify('selfies/u1/a.jpg', '1', sig), null);
  assert.equal(files.url(null, null), null);
  await assert.rejects(files.saveJpeg('../escape.jpg', Buffer.from([0xff, 0xd8, 0xff])));
});

test('isJpeg checks the magic bytes', () => {
  assert.ok(isJpeg(Buffer.from([0xff, 0xd8, 0xff, 0xe0])));
  assert.ok(!isJpeg(Buffer.from('GIF89a')));
  assert.ok(!isJpeg(undefined));
});
