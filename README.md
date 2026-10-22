# Smart Attendance

Selfie + GPS attendance for a single company, built with Flutter, a Node.js
REST API and MySQL.

| Part | Platform | Entry point |
|---|---|---|
| **Employee app** — check in / check out with a live selfie at a geofenced site | Android | `lib/main_employee.dart` |
| **Employer control panel** — dashboard, employees, sites, shifts, reports, review queue | Web | `lib/main_admin.dart` |
| **API server** — auth, data, photo storage, punch verification | Node.js 22 + MySQL 8 | `server/` |

Both apps share one codebase (`lib/core/`) and talk to the same API.

## Features

**Employee app (Android)**
- Email/password login; accounts are created by the admin, who also sets new passwords.
- **Device lock** — the first phone an employee signs in on is bound to the account. Other phones are refused until the admin resets the device.
- **Face enrollment** — on first login the employee registers a reference selfie.
- **Check in / Check out**
  1. High-accuracy GPS fix; **fake/mock GPS is rejected**.
  2. **Geofence** — the punch is refused if the employee is outside the radius of every site they are assigned to.
  3. **Live selfie** from the front camera (no gallery). ML Kit requires exactly one face.
  4. **Face embedding** computed on the phone (MobileFaceNet) and sent with the photo.
  5. The **server re-checks everything**: device binding, mock GPS, geofence, one check-in and one check-out per day, and the face match against the enrolled face. Time and calendar day come from the **server clock**. A face mismatch does **not** block the punch; it is recorded and **flagged for admin review**. Weak GPS accuracy is flagged the same way.
- Today's status, worked hours, and a monthly history with present/late/half-day/absent counts.

**Admin panel (Flutter Web)**
- **Dashboard** — today's present/late/absent/pending-review counts, a table with selfies, a map of check-in locations and a 7-day chart.
- **Review queue** — flagged punches shown next to the registered face with map and face-match score; approve or reject (rejected = absent).
- **Employees** — add (creates the login), edit, deactivate, assign shift and allowed sites, reset device, reset face, set a new password.
- **Sites** — click on a map to set the location; radius slider (25–1000 m).
- **Shifts** — start/end, grace minutes, half-day-if-later-than, minimum hours for a full day, work days.
- **Reports** — any date range, per-employee filter, summary and daily detail; export **Excel, CSV, PDF**.
- Lists refresh every 30–60 s and immediately after any change.

Status (present / late / half day / absent / weekly off) is **derived when read** from the stored server timestamps and the shift rules — it is never stored, so a tampered phone clock can't change it and editing a shift re-evaluates past days.

## Project layout

```
lib/
  main_employee.dart          Android app entry
  main_admin.dart             Web admin entry
  core/
    app_config.dart           thresholds (GPS timeout, selfie size, …)
    models/                   AppUser, Site, Shift, AttendanceRecord/Punch
    data/                     ApiClient, repositories, Riverpod providers
    utils/                    geofence maths, face maths, attendance rules
  employee/                   gate, screens, device/location/face/punch services
  admin/                      shell, screens, report builder & exporter
server/
  sql/                        MySQL schema migrations (applied on start)
  src/                        Express API: routes/, auth, file store, punch rules
  test/                       unit tests + end-to-end API tests
deploy/                       docker-compose and nginx config (see DEPLOY.md)
assets/models/                put mobilefacenet.tflite here (see below)
test/                         Flutter unit tests for the core logic
```

## Run locally

### 1. Prerequisites
- Flutter 3.47 stable (Dart 3.13) and the Android SDK (Android Studio).
- Node.js 22+.
- MySQL 8.0.13+ (a local install, or your VM's).

### 2. Database and API

In MySQL, as root:
```sql
CREATE DATABASE smart_attendance CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'attendance'@'localhost' IDENTIFIED BY 'choose-a-password';
GRANT ALL PRIVILEGES ON smart_attendance.* TO 'attendance'@'localhost';
```

Then:
```bash
cd server
npm install
cp .env.example .env     # DB_HOST=127.0.0.1, DB_PASSWORD, JWT_SECRET, APP_TIMEZONE
npm run migrate
npm run create-admin -- --email you@example.com --name "Your Name"
npm run dev              # http://localhost:8080/api/health
```

### 3. Admin panel (web)
```bash
flutter run -d chrome -t lib/main_admin.dart --dart-define=API_URL=http://localhost:8080
```

### 4. Employee app (Android)
On the emulator, the API on your PC is `10.0.2.2:8080`, which debug builds use by default:
```bash
flutter run -t lib/main_employee.dart
```
On a real phone on the same Wi-Fi, use your PC's LAN IP:
```bash
flutter run -t lib/main_employee.dart --dart-define=API_URL=http://192.168.1.20:8080
```
Debug builds allow plain HTTP; release builds require HTTPS.

### 5. Add the face recognition model
Download a **MobileFaceNet** TFLite model (112×112 RGB input, 128- or 192-float output — e.g. the widely used `mobilefacenet.tflite` from open-source Flutter face-recognition samples; check its licence) and save it as:
```
assets/models/mobilefacenet.tflite
```
The model's input/output sizes are read at runtime. **Without the model** the app still works, but every punch is flagged *"Face could not be verified"* and face enrollment will report the model as missing.

Tune `FACE_MATCH_THRESHOLD` in `server/.env` (default `0.55` cosine similarity) after testing with your staff: raise it if impostors pass, lower it if genuine staff are flagged too often.

### 6. First-day checklist
1. Admin panel → **Sites**: add your office(s), set radius (100 m is a good start; GPS indoors is often ±20–50 m).
2. **Shifts**: add your shift(s).
3. **Employees**: add staff with an initial password, assign shift and sites.
4. Employee installs the APK, signs in (binds phone), registers face, checks in.

## Production

See **[DEPLOY.md](DEPLOY.md)**: Docker Compose on the VM with nginx, Let's Encrypt
HTTPS, the VM's MySQL, backups and updates.

Before publishing the APK: change `applicationId` in `android/app/build.gradle.kts`, and set up a release signing key (currently signs with the debug key).

## Security model

- **Authentication** — bcrypt password hashes and signed JWT tokens (30 days by default). Setting a new password signs the user out everywhere. Login is rate-limited.
- **Authorization** — every request loads the user from MySQL: employees read only their own profile and records, admins everything. Deactivated users are refused by every endpoint except reading their own profile, and cannot sign in.
- **Punch verification on the server** — the server decides the time and the day (`APP_TIMEZONE`), rejects mock GPS, an unbound or different device and positions outside the geofence, computes the face match itself, and allows one check-in and one check-out per day (database keys make this race-free). The employee can't clear a flag.
- **Photos** — stored on the server disk, outside the web root. The API hands out signed links that expire after 3–6 hours; JPEG only, 5 MB max.
- **Device binding and face enrollment** happen once; only an admin can reset them.

### Known limitations
- **The phone still produces the evidence.** GPS coordinates and the face embedding come from the app. The server re-checks them, but a modified APK could send a fake position or a replayed embedding; the selfie, the map and the review queue are the safety net.
- **Mock-location detection** uses Android's `isMock` flag. It catches common fake-GPS apps, but not rooted-device spoofing.
- **Device binding** uses an id stored in app data, so reinstalling the app or clearing its data needs an admin device reset (by design).
- **Time zone.** One zone (`APP_TIMEZONE`) decides the calendar day; shift times are evaluated in the viewer's local time zone. Night shifts that cross midnight are not specially handled.
- **No password-reset email.** The admin sets a new password from the panel.
- **Map tiles.** The admin panel uses OpenStreetMap tiles; for heavy use, switch to a commercial tile provider per the OSM tile usage policy.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```
Flutter tests cover the geofence and face maths, the attendance status rules, the report aggregation, and the CSV/Excel export.

**Server tests** (from `server/`):
```bash
npm test
```
runs the unit tests (the API tests are skipped), and
```bash
npm run test:api
```
adds the end-to-end API tests against MySQL. `test:api` reads `server/.env.test` (`TEST_DB_HOST`, `TEST_DB_PORT`, `TEST_DB_USER`, `TEST_DB_PASSWORD`, `TEST_DB_NAME`); the database it names is **wiped** on every run, so use a dedicated one. They cover login, admin-only access, device binding, face enrollment, server time, geofence and mock-GPS rejection, write-once check-in/out, flags and review, photo-link signing, deactivation and password changes.

## Data model (MySQL)

```
users        id, name, email, password_hash, phone, employee_code, role, active,
             shift_id → shifts, device_id, device_model, face_embedding (JSON),
             face_path, token_version
user_sites   user_id → users, site_id → sites       (no rows = any site)
sites        id, name, address, lat, lng, radius_meters
shifts       id, name, start_time "HH:mm", end_time, grace_minutes,
             half_day_after_minutes, min_full_day_minutes, work_days (JSON)
attendance   id "{userId}_{yyyy-MM-dd}", user_id, employee_name, date, shift_id,
             flagged, reviewed, review_decision, reviewed_by, reviewed_at, review_note
punches      (attendance_id, kind in|out) primary key, time (UTC), lat, lng,
             accuracy, site_id, site_name, distance_meters, photo_path,
             face_score, flag_reasons (JSON), device_id
files        uploads/selfies/{userId}/{date}_{in|out}_{ts}.jpg
             uploads/faces/{userId}/{ts}.jpg
```

Full schema: `server/sql/001_init.sql`.
