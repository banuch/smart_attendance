// End-to-end API tests against a real, disposable MySQL database.
//
//   TEST_DB_HOST=127.0.0.1 TEST_DB_PORT=3307 TEST_DB_USER=root \
//   TEST_DB_PASSWORD=... TEST_DB_NAME=sa_test npm test
//
// The database named in TEST_DB_NAME is wiped. Skipped when it is not set.
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';

import bcrypt from 'bcryptjs';
import mysql from 'mysql2/promise';
import request from 'supertest';

import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import { migrate } from '../src/migrate.js';

const env = process.env;
const enabled = Boolean(env.TEST_DB_NAME);

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);
const FACE = Array.from({ length: 128 }, (_, i) => (i % 7) / 7);
const OTHER_FACE = Array.from({ length: 128 }, (_, i) => (i % 2 ? 1 : -1));
const OFFICE = { lat: 12.9716, lng: 77.5946 };

describe('API', { skip: !enabled && 'set TEST_DB_* to run' }, () => {
  let pool;
  let app;
  let adminToken;
  let empToken;
  let empId;
  let siteId;
  let recordId;

  const as = (token) => ({
    get: (url) => request(app).get(url).set('Authorization', `Bearer ${token}`),
    post: (url) => request(app).post(url).set('Authorization', `Bearer ${token}`),
    put: (url) => request(app).put(url).set('Authorization', `Bearer ${token}`),
    delete: (url) => request(app).delete(url).set('Authorization', `Bearer ${token}`),
  });

  const punch = (token, fields = {}) => {
    const f = { ...OFFICE, accuracy: 10, deviceId: 'device-aaaa-1111', embedding: JSON.stringify(FACE), ...fields };
    let r = as(token).post('/api/attendance/punch');
    for (const [k, v] of Object.entries(f)) if (v !== undefined) r = r.field(k, String(v));
    return r.attach('photo', JPEG, { filename: 'selfie.jpg', contentType: 'image/jpeg' });
  };

  before(async () => {
    const db = {
      host: env.TEST_DB_HOST || '127.0.0.1',
      port: Number(env.TEST_DB_PORT) || 3306,
      user: env.TEST_DB_USER || 'root',
      password: env.TEST_DB_PASSWORD || '',
      database: env.TEST_DB_NAME,
    };
    const root = await mysql.createConnection({ ...db, database: undefined });
    await root.query(`DROP DATABASE IF EXISTS \`${db.database}\``);
    await root.query(`CREATE DATABASE \`${db.database}\``);
    await root.end();
    await migrate(db, () => {});

    const config = loadConfig({
      JWT_SECRET: 'test-secret-'.padEnd(40, 'x'),
      UPLOAD_DIR: await mkdtemp(path.join(os.tmpdir(), 'sa-uploads-')),
      APP_TIMEZONE: 'Asia/Kolkata',
    });
    config.db = db;
    pool = createPool(db);
    app = createApp({ pool, config });

    await pool.query(
      `INSERT INTO users (id, name, email, password_hash, role) VALUES (UUID(), 'Boss', 'boss@test.local', ?, 'admin')`,
      [await bcrypt.hash('admin-pass-1', 4)],
    );
  });

  after(async () => pool?.end());

  test('login rejects a wrong password and accepts the right one', async () => {
    await request(app).post('/api/auth/login').send({ email: 'boss@test.local', password: 'nope' }).expect(401);
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'BOSS@test.local', password: 'admin-pass-1' })
      .expect(200);
    assert.equal(res.body.user.role, 'admin');
    adminToken = res.body.token;
  });

  test('requests without a token are refused', async () => {
    await request(app).get('/api/sites').expect(401);
    await request(app).get('/api/sites').set('Authorization', 'Bearer garbage').expect(401);
  });

  test('admin creates a site, a shift and an employee', async () => {
    const site = await as(adminToken).post('/api/sites')
      .send({ name: 'HQ', ...OFFICE, radiusMeters: 100 }).expect(201);
    siteId = site.body.id;
    await as(adminToken).post('/api/sites').send({ name: 'Bad', lat: 200, lng: 0, radiusMeters: 100 }).expect(400);

    const shift = await as(adminToken).post('/api/shifts')
      .send({ name: 'General', start: '09:00', end: '18:00', workDays: [5, 1, 1] }).expect(201);
    assert.deepEqual(shift.body.workDays, [1, 5]);

    const emp = await as(adminToken).post('/api/users').send({
      name: 'Asha', email: 'asha@test.local', password: 'emp-pass-1',
      siteIds: [siteId], shiftId: shift.body.id,
    }).expect(201);
    empId = emp.body.uid;
    assert.deepEqual(emp.body.siteIds, [siteId]);
    assert.equal(emp.body.faceEnrolled, false);

    await as(adminToken).post('/api/users')
      .send({ name: 'Dup', email: 'asha@test.local', password: 'emp-pass-1' }).expect(409);
    await as(adminToken).post('/api/users')
      .send({ name: 'Short', email: 'short@test.local', password: '123' }).expect(400);
  });

  test('employees cannot use admin endpoints', async () => {
    const res = await request(app).post('/api/auth/login')
      .send({ email: 'asha@test.local', password: 'emp-pass-1' }).expect(200);
    empToken = res.body.token;
    await as(empToken).get('/api/users').expect(403);
    await as(empToken).post('/api/sites').send({ name: 'X', ...OFFICE, radiusMeters: 100 }).expect(403);
    await as(empToken).get('/api/attendance/pending').expect(403);
    await as(empToken).get('/api/sites').expect(200);
  });

  test('punching needs a bound device', async () => {
    await punch(empToken).expect(403);
    await as(empToken).post('/api/me/device').send({ deviceId: 'device-aaaa-1111', deviceModel: 'Pixel' }).expect(200);
    await as(empToken).post('/api/me/device').send({ deviceId: 'device-bbbb-2222' }).expect(409);
    await punch(empToken, { deviceId: 'device-bbbb-2222' }).expect(403);
  });

  test('face enrolls once', async () => {
    await as(empToken).post('/api/me/face').field('embedding', JSON.stringify(FACE)).expect(400);
    const res = await as(empToken).post('/api/me/face')
      .field('embedding', JSON.stringify(FACE))
      .attach('photo', JPEG, { filename: 'f.jpg', contentType: 'image/jpeg' })
      .expect(200);
    assert.equal(res.body.faceEnrolled, true);
    assert.match(res.body.faceUrl, /\/files\/faces\//);
    await as(empToken).post('/api/me/face')
      .field('embedding', JSON.stringify(FACE))
      .attach('photo', JPEG, { filename: 'f.jpg', contentType: 'image/jpeg' })
      .expect(409);
  });

  test('server rejects mock GPS, outside-geofence punches and non-JPEG photos', async () => {
    await punch(empToken, { mocked: true }).expect(400);
    const far = await punch(empToken, { lat: OFFICE.lat + 0.01 }).expect(422);
    assert.match(far.body.error, /m from HQ/);
    await as(empToken).post('/api/attendance/punch')
      .field('lat', OFFICE.lat).field('lng', OFFICE.lng).field('accuracy', 5).field('deviceId', 'device-aaaa-1111')
      .attach('photo', Buffer.from('GIF89a'), { filename: 'x.gif', contentType: 'image/gif' })
      .expect(400);
  });

  test('check-in uses the server clock and a matching face is not flagged', async () => {
    const before = Date.now();
    const res = await punch(empToken, { time: '2000-01-01T00:00:00Z' }).expect(201);
    assert.equal(res.body.kind, 'in');
    const rec = res.body.record;
    recordId = rec.id;
    assert.equal(rec.uid, empId);
    assert.equal(rec.flagged, false);
    assert.equal(rec.checkIn.siteName, 'HQ');
    assert.ok(Math.abs(rec.checkIn.faceScore - 1) < 1e-9);
    const t = Date.parse(rec.checkIn.time);
    assert.ok(t >= before - 1000 && t <= Date.now() + 1000, 'server time, not client time');

    const today = await as(empToken).get('/api/attendance/today').expect(200);
    assert.equal(today.body.record.id, recordId);
    assert.equal(recordId, `${empId}_${today.body.date}`);
  });

  test('photo links work, and tampered links do not', async () => {
    const { body } = await as(empToken).get('/api/attendance/today');
    const url = new URL(body.record.checkIn.photoUrl);
    const ok = await request(app).get(url.pathname + url.search).expect(200);
    assert.ok(ok.body.length > 0 || ok.text?.length > 0);
    await request(app).get(url.pathname + url.search.replace(/sig=./, 'sig=A')).expect(404);
    await request(app).get(url.pathname).expect(404);
  });

  test('a mismatching check-out face flags the day for review', async () => {
    const res = await punch(empToken, { embedding: JSON.stringify(OTHER_FACE), accuracy: 120 }).expect(201);
    assert.equal(res.body.kind, 'out');
    assert.equal(res.body.record.flagged, true);
    assert.deepEqual(res.body.record.checkOut.flagReasons, ['face_mismatch', 'low_gps_accuracy']);
    await punch(empToken).expect(409);
  });

  test('admin sees the pending review and approves it', async () => {
    const pending = await as(adminToken).get('/api/attendance/pending').expect(200);
    assert.deepEqual(pending.body.map((r) => r.id), [recordId]);
    await as(empToken).post(`/api/attendance/${recordId}/review`).send({ decision: 'approved' }).expect(403);
    const res = await as(adminToken).post(`/api/attendance/${recordId}/review`)
      .send({ decision: 'approved', note: 'Glasses' }).expect(200);
    assert.equal(res.body.reviewed, true);
    assert.equal(res.body.reviewDecision, 'approved');
    assert.equal((await as(adminToken).get('/api/attendance/pending')).body.length, 0);
  });

  test('range queries: employees only see their own records', async () => {
    const { body: { date } } = await as(empToken).get('/api/attendance/today');
    const all = await as(adminToken).get(`/api/attendance?from=${date}&to=${date}`).expect(200);
    assert.equal(all.body.length, 1);
    const mine = await as(empToken).get(`/api/attendance?from=${date}&to=${date}&uid=00000000-0000-4000-8000-000000000000`).expect(200);
    assert.equal(mine.body.length, 1, 'uid filter ignored for employees');
    await as(adminToken).get('/api/attendance?from=2026-02-01&to=2026-01-01').expect(400);
  });

  test('admin cannot lock themself out', async () => {
    const me = await as(adminToken).get('/api/me').expect(200);
    await as(adminToken).put(`/api/users/${me.body.uid}`)
      .send({ name: 'Boss', email: 'boss@test.local', role: 'employee' }).expect(400);
  });

  test('deactivation blocks punching; a new password signs the user out', async () => {
    const profile = { name: 'Asha', email: 'asha@test.local', siteIds: [siteId] };
    await as(adminToken).put(`/api/users/${empId}`).send({ ...profile, active: false }).expect(200);
    const me = await as(empToken).get('/api/me').expect(200);
    assert.equal(me.body.active, false);
    await as(empToken).get('/api/attendance/today').expect(403);
    await request(app).post('/api/auth/login').send({ email: 'asha@test.local', password: 'emp-pass-1' }).expect(403);

    await as(adminToken).put(`/api/users/${empId}`).send({ ...profile, active: true }).expect(200);
    await as(adminToken).post(`/api/users/${empId}/password`).send({ password: 'new-pass-22' }).expect(200);
    await as(empToken).get('/api/me').expect(401);
    await request(app).post('/api/auth/login').send({ email: 'asha@test.local', password: 'new-pass-22' }).expect(200);
  });

  test('admin resets device and face', async () => {
    const d = await as(adminToken).post(`/api/users/${empId}/reset-device`).expect(200);
    assert.equal(d.body.deviceId, null);
    const f = await as(adminToken).post(`/api/users/${empId}/reset-face`).expect(200);
    assert.equal(f.body.faceEnrolled, false);
  });

  test('deleting a site removes it from assignments', async () => {
    await as(adminToken).delete(`/api/sites/${siteId}`).expect(204);
    const users = await as(adminToken).get('/api/users').expect(200);
    assert.deepEqual(users.body.find((u) => u.uid === empId).siteIds, []);
    await as(adminToken).delete(`/api/sites/${siteId}`).expect(404);
  });
});
