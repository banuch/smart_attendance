import { fromSqlTime } from './lib/dates.js';

// ---------------- users ----------------

export async function siteIdsByUser(db, userIds) {
  const map = new Map(userIds.map((id) => [id, []]));
  if (userIds.length === 0) return map;
  const [rows] = await db.query(
    'SELECT user_id, site_id FROM user_sites WHERE user_id IN (?)',
    [userIds],
  );
  for (const r of rows) map.get(r.user_id)?.push(r.site_id);
  return map;
}

export function userJson(row, siteIds, files, req) {
  return {
    uid: row.id,
    name: row.name,
    email: row.email,
    phone: row.phone,
    employeeCode: row.employee_code,
    role: row.role,
    active: !!row.active,
    siteIds,
    shiftId: row.shift_id,
    deviceId: row.device_id,
    deviceModel: row.device_model,
    faceEnrolled: row.face_embedding != null,
    faceUrl: files.url(row.face_path, req),
  };
}

export async function loadUserJson(db, id, files, req) {
  const [rows] = await db.query('SELECT * FROM users WHERE id = ?', [id]);
  if (!rows[0]) return null;
  const sites = await siteIdsByUser(db, [id]);
  return userJson(rows[0], sites.get(id), files, req);
}

// ---------------- sites & shifts ----------------

export const siteJson = (r) => ({
  id: r.id,
  name: r.name,
  address: r.address,
  lat: r.lat,
  lng: r.lng,
  radiusMeters: r.radius_meters,
});

export const shiftJson = (r) => ({
  id: r.id,
  name: r.name,
  start: r.start_time,
  end: r.end_time,
  graceMinutes: r.grace_minutes,
  halfDayAfterMinutes: r.half_day_after_minutes,
  minFullDayMinutes: r.min_full_day_minutes,
  workDays: r.work_days,
});

// ---------------- attendance ----------------

const PUNCH_COLUMNS = [
  'time', 'lat', 'lng', 'accuracy', 'site_id', 'site_name', 'distance_meters',
  'photo_path', 'face_score', 'flag_reasons', 'device_id',
];

const select = (alias) => PUNCH_COLUMNS.map((c) => `${alias}.${c} AS ${alias}_${c}`).join(', ');

/** Attendance rows joined with their check-in and (optional) check-out. */
export const ATTENDANCE_SELECT = `
  SELECT a.*, ${select('pi')}, ${select('po')}
  FROM attendance a
  JOIN punches pi ON pi.attendance_id = a.id AND pi.kind = 'in'
  LEFT JOIN punches po ON po.attendance_id = a.id AND po.kind = 'out'`;

function punchJson(row, alias, files, req) {
  if (row[`${alias}_time`] == null) return null;
  const v = (c) => row[`${alias}_${c}`];
  return {
    time: fromSqlTime(v('time')),
    lat: v('lat'),
    lng: v('lng'),
    accuracy: v('accuracy'),
    siteId: v('site_id'),
    siteName: v('site_name'),
    distanceMeters: v('distance_meters'),
    photoUrl: files.url(v('photo_path'), req),
    photoPath: v('photo_path'),
    faceScore: v('face_score'),
    flagReasons: v('flag_reasons') ?? [],
    deviceId: v('device_id'),
  };
}

export function attendanceJson(row, files, req) {
  return {
    id: row.id,
    uid: row.user_id,
    employeeName: row.employee_name,
    date: row.date,
    shiftId: row.shift_id,
    checkIn: punchJson(row, 'pi', files, req),
    checkOut: punchJson(row, 'po', files, req),
    flagged: !!row.flagged,
    reviewed: !!row.reviewed,
    reviewDecision: row.review_decision,
    reviewNote: row.review_note,
  };
}

export async function loadAttendance(db, id, files, req) {
  const [rows] = await db.query(`${ATTENDANCE_SELECT} WHERE a.id = ?`, [id]);
  return rows[0] ? attendanceJson(rows[0], files, req) : null;
}
