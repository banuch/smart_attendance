# Smart Attendance

Selfie + GPS attendance for a single company, built with Flutter and Firebase.

| Part | Platform | Entry point |
|---|---|---|
| **Employee app** — check in / check out with a live selfie at a geofenced site | Android | `lib/main_employee.dart` |
| **Employer control panel** — dashboard, employees, sites, shifts, reports, review queue | Web | `lib/main_admin.dart` |

Both share one codebase (`lib/core/`) and one Firebase project.

## Features

**Employee app (Android)**
- Email/password login; accounts are created by the admin.
- **Device lock** — the first phone an employee signs in on is bound to the account. Other phones are refused until the admin resets the device.
- **Face enrollment** — on first login the employee registers a reference selfie.
- **Check in / Check out**
  1. High-accuracy GPS fix; **fake/mock GPS is rejected**.
  2. **Geofence** — the punch is refused if the employee is outside the radius of every site they are assigned to.
  3. **Live selfie** from the front camera (no gallery). ML Kit requires exactly one face.
  4. **Face match** against the enrolled face (MobileFaceNet). A mismatch does **not** block the punch; it is recorded and **flagged for admin review**. Weak GPS accuracy is flagged the same way.
  5. Photo uploaded to Storage; record written with the **server timestamp**.
- Today's status, worked hours, and a monthly history with present/late/half-day/absent counts.

**Admin panel (Flutter Web)**
- **Dashboard** — today's present/late/absent/pending-review counts, a table with selfies, a map of check-in locations and a 7-day chart.
- **Review queue** — flagged punches shown next to the registered face with map and face-match score; approve or reject (rejected = absent).
- **Employees** — add (creates the login), edit, deactivate, assign shift and allowed sites, reset device, reset face, send password-reset email.
- **Sites** — click on a map to set the location; radius slider (25–1000 m).
- **Shifts** — start/end, grace minutes, half-day-if-later-than, minimum hours for a full day, work days.
- **Reports** — any date range, per-employee filter, summary and daily detail; export **Excel, CSV, PDF**.

Status (present / late / half day / absent / weekly off) is **derived when read** from the stored server timestamps and the shift rules — it is never stored, so a tampered phone clock can't change it and editing a shift re-evaluates past days.

## Project layout

```
lib/
  main_employee.dart          Android app entry
  main_admin.dart             Web admin entry
  firebase_options.dart       PLACEHOLDER – regenerate with flutterfire
  core/
    app_config.dart           thresholds (face match, GPS accuracy, …)
    models/                   AppUser, Site, Shift, AttendanceRecord/Punch
    data/                     Firestore repositories + Riverpod providers
    utils/                    geofence maths, face maths, attendance rules
  employee/                   gate, screens, device/location/face/punch services
  admin/                      shell, screens, report builder & exporter
firestore.rules  storage.rules  firestore.indexes.json  firebase.json  cors.json
assets/models/                put mobilefacenet.tflite here (see below)
test/                         unit tests for the core logic
```

## Setup

### 1. Prerequisites
- Flutter 3.47 stable (Dart 3.13) and the Android SDK (Android Studio).
- Node.js + Firebase CLI: `npm i -g firebase-tools`, then `firebase login`.
- FlutterFire CLI: `dart pub global activate flutterfire_cli`.

### 2. Create the Firebase project
1. In the [Firebase console](https://console.firebase.google.com) create a project.
2. **Authentication → Sign-in method** → enable **Email/Password**.
3. **Firestore Database** → create (production mode, region near you).
4. **Storage** → get started.

### 3. Connect the app
```bash
flutterfire configure --platforms=android,web
```
This overwrites `lib/firebase_options.dart` with your project's keys. (It may also offer to add `google-services.json`; that's fine but not required.)

### 4. Deploy rules and indexes
```bash
firebase use --add            # pick your project
firebase deploy --only firestore:rules,firestore:indexes,storage
```

### 5. Allow the admin panel to load selfies (CORS)
Browsers need CORS on the Storage bucket to display images:
```bash
gsutil cors set cors.json gs://<your-bucket>   # bucket name from Storage page
```
You can restrict `origin` in `cors.json` to your admin URL.

### 6. Add the face recognition model
Download a **MobileFaceNet** TFLite model (112×112 RGB input, 128- or 192-float output — e.g. the widely used `mobilefacenet.tflite` from open-source Flutter face-recognition samples; check its licence) and save it as:
```
assets/models/mobilefacenet.tflite
```
The model's input/output sizes are read at runtime. **Without the model** the app still works, but every punch is flagged *"Face could not be verified"* and face enrollment will report the model as missing.

Tune `faceMatchThreshold` in `lib/core/app_config.dart` (default `0.55` cosine similarity) after testing with your staff: raise it if impostors pass, lower it if genuine staff are flagged too often.

### 7. Create the first admin
1. Firebase console → **Authentication → Add user** (email + password). Copy the **User UID**.
2. Firestore → start collection **`users`** → document ID = that UID, fields:

   | field | type | value |
   |---|---|---|
   | `name` | string | Your name |
   | `email` | string | the same email |
   | `role` | string | `admin` |
   | `active` | boolean | `true` |

After that, everything else (more admins, employees, sites, shifts) is done from the panel.

### 8. Run / build

**Admin panel (web)**
```bash
flutter run -d chrome -t lib/main_admin.dart
flutter build web -t lib/main_admin.dart
firebase deploy --only hosting      # serves build/web
```

**Employee app (Android)**
```bash
flutter run -t lib/main_employee.dart
flutter build apk --release -t lib/main_employee.dart
```
Before publishing: change `applicationId` in `android/app/build.gradle.kts`, and set up a release signing key (currently signs with the debug key).

### 9. First-day checklist
1. Admin panel → **Sites**: add your office(s), set radius (100 m is a good start; GPS indoors is often ±20–50 m).
2. **Shifts**: add your shift(s).
3. **Employees**: add staff with an initial password, assign shift and sites.
4. Employee installs the APK, signs in (binds phone), registers face, checks in.

## Security model

- **Firestore rules** (`firestore.rules`)
  - Employees read only their own profile and records; admins read everything.
  - Employees can update their own profile only to bind a device (when unbound) or enroll a face (when not enrolled).
  - An attendance record can be **created only by its owner**, with id `{uid}_{date}`, and the punch `time` must equal the **server time** (`request.time`).
  - Check-out can be written once; check-in can never be edited. The `flagged` flag cannot be cleared by the employee.
  - Only admins can review, delete records, or manage sites/shifts/users.
- Storage rules check the admin role via Firestore (cross-service rules); the first `firebase deploy` asks you to allow this.
- **Storage rules** — employees can create (never overwrite) their own selfies; only the owner and admins can read.
- Inactive users are blocked by both the app and the rules.

### Known limitations
- **Checks run on the phone.** Geofence, mock-GPS and face matching run in the app; the backend enforces identity, server time and write-once. A determined attacker with a modified APK could bypass them. To harden, move verification into Cloud Functions (needs the Blaze plan). The admin review queue and map view are the safety net.
- **Mock-location detection** uses Android's `isMock` flag. It catches common fake-GPS apps, but not rooted-device spoofing.
- **Device binding** uses an id stored in app data, so reinstalling the app or clearing its data needs an admin device reset (by design).
- **Deactivating** an employee blocks them in the app and in the rules, but does not disable their Firebase Auth login. Disable it in the console if needed.
- **Time zone.** Shift times are evaluated in the viewer's local time zone, which assumes the admin and staff share one time zone. Night shifts that cross midnight are not specially handled.
- **Map tiles.** The admin panel uses OpenStreetMap tiles; for heavy use, switch to a commercial tile provider per the OSM tile usage policy.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```
Tests cover the geofence and face maths, the attendance status rules, the report aggregation, and the CSV/Excel export.

**Security rules tests** (Firestore emulator; needs Node.js and Java):
```bash
cd rules_test && npm install && npm test
```
They cover 33 cases, including server-time enforcement, write-once check-out, flags the employee can't clear, device and face binding, and admin-only actions.

## Data model

```
users/{uid}          name, email, phone, employeeCode, role, active,
                     siteIds[], shiftId, deviceId, deviceModel,
                     faceEmbedding[], faceUrl, facePath
sites/{id}           name, address, lat, lng, radiusMeters
shifts/{id}          name, start "HH:mm", end, graceMinutes,
                     halfDayAfterMinutes, minFullDayMinutes, workDays[1..7]
attendance/{uid_yyyy-MM-dd}
                     uid, employeeName, date, shiftId,
                     checkIn{time, lat, lng, accuracy, siteId, siteName,
                             distanceMeters, photoUrl, photoPath,
                             faceScore, flagReasons[], deviceId},
                     checkOut{…same…},
                     flagged, reviewed, reviewDecision, reviewedBy,
                     reviewedAt, reviewNote
Storage: selfies/{uid}/{date}_{in|out}_{ts}.jpg, faces/{uid}/{ts}.jpg
```
