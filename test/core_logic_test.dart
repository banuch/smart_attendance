import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/admin/services/report_builder.dart';
import 'package:smart_attendance/admin/services/report_exporter.dart';
import 'package:smart_attendance/core/models/app_user.dart';
import 'package:smart_attendance/core/models/attendance_record.dart';
import 'package:smart_attendance/core/models/shift.dart';
import 'package:smart_attendance/core/models/site.dart';
import 'package:smart_attendance/core/utils/attendance_rules.dart';
import 'package:smart_attendance/core/utils/dates.dart';
import 'package:smart_attendance/core/utils/face_math.dart';
import 'package:smart_attendance/core/utils/geo.dart';

Punch punchAt(DateTime t) => Punch(
  time: t,
  lat: 0,
  lng: 0,
  accuracy: 5,
  siteId: 's1',
  siteName: 'HQ',
  distanceMeters: 10,
  photoUrl: '',
  photoPath: '',
);

AttendanceRecord record(
  String uid,
  DateTime inTime, {
  DateTime? outTime,
  ReviewDecision? decision,
  String? shiftId = 'day',
}) => AttendanceRecord(
  id: AttendanceRecord.docId(uid, dateKey(inTime)),
  uid: uid,
  employeeName: uid,
  date: dateKey(inTime),
  shiftId: shiftId,
  checkIn: punchAt(inTime),
  checkOut: outTime == null ? null : punchAt(outTime),
  reviewDecision: decision,
  reviewed: decision != null,
);

const dayShift = Shift(
  id: 'day',
  name: 'Day',
  startMinutes: 9 * 60,
  endMinutes: 18 * 60,
  graceMinutes: 10,
  halfDayAfterMinutes: 120,
  minFullDayMinutes: 360,
  workDays: [1, 2, 3, 4, 5],
);

void main() {
  // 2026-10-12 is a Monday.
  final monday = DateTime(2026, 10, 12);
  final later = DateTime(2026, 10, 20, 12);

  group('geo', () {
    test('haversine distance is accurate', () {
      // ~111.2 km per degree of latitude.
      expect(distanceMeters(0, 0, 1, 0), closeTo(111195, 50));
      expect(distanceMeters(12.9716, 77.5946, 12.9716, 77.5946), 0);
      // Two points ~100 m apart.
      expect(
        distanceMeters(12.9716, 77.5946, 12.9725, 77.5946),
        closeTo(100, 1),
      );
    });

    test('nearestSite prefers a site the point is inside', () {
      const big = Site(
        id: 'big',
        name: 'Big',
        lat: 0,
        lng: 0.002,
        radiusMeters: 500,
      );
      const small = Site(
        id: 'small',
        name: 'Small',
        lat: 0,
        lng: 0.0005,
        radiusMeters: 20,
      );
      final m = nearestSite(0, 0, [small, big])!;
      expect(m.site.id, 'big');
      expect(m.inside, isTrue);
    });

    test('nearestSite reports outside when out of every radius', () {
      const hq = Site(id: 'hq', name: 'HQ', lat: 0, lng: 0, radiusMeters: 100);
      final m = nearestSite(0.01, 0, [hq])!;
      expect(m.inside, isFalse);
      expect(m.distance, closeTo(1112, 5));
      expect(nearestSite(0, 0, const []), isNull);
    });
  });

  group('face math', () {
    test('cosine similarity', () {
      expect(cosineSimilarity([1, 0], [1, 0]), closeTo(1, 1e-9));
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0, 1e-9));
      expect(cosineSimilarity([1, 0], [-1, 0]), closeTo(-1, 1e-9));
      expect(cosineSimilarity([1, 2], [1]), 0);
    });

    test('l2Normalize yields unit vectors', () {
      final v = l2Normalize([3, 4]);
      expect(v[0], closeTo(0.6, 1e-9));
      expect(v[1], closeTo(0.8, 1e-9));
      expect(l2Normalize([0, 0]), [0, 0]);
    });
  });

  group('dates', () {
    test('hm round trip', () {
      expect(parseHm('09:30'), 570);
      expect(formatHm(570), '09:30');
      expect(formatDuration(125), '2h 05m');
    });

    test('daysInRange is inclusive', () {
      final days = daysInRange(monday, DateTime(2026, 10, 14, 23)).toList();
      expect(days.map(dateKey), ['2026-10-12', '2026-10-13', '2026-10-14']);
    });
  });

  group('AttendanceRules', () {
    DayEvaluation eval(AttendanceRecord? r, {DateTime? day}) =>
        AttendanceRules.evaluate(r, dayShift, day: day ?? monday, now: later);

    test('on time within grace', () {
      final e = eval(
        record(
          'a',
          DateTime(2026, 10, 12, 9, 8),
          outTime: DateTime(2026, 10, 12, 18),
        ),
      );
      expect(e.status, DayStatus.present);
      expect(e.lateMinutes, 0);
      expect(e.workedMinutes, 532);
    });

    test('late after grace', () {
      final e = eval(
        record(
          'a',
          DateTime(2026, 10, 12, 9, 25),
          outTime: DateTime(2026, 10, 12, 18),
        ),
      );
      expect(e.status, DayStatus.late);
      expect(e.lateMinutes, 25);
    });

    test('half day when very late', () {
      final e = eval(
        record(
          'a',
          DateTime(2026, 10, 12, 11, 30),
          outTime: DateTime(2026, 10, 12, 18),
        ),
      );
      expect(e.status, DayStatus.halfDay);
    });

    test('half day when worked too little', () {
      final e = eval(
        record(
          'a',
          DateTime(2026, 10, 12, 9),
          outTime: DateTime(2026, 10, 12, 13),
        ),
      );
      expect(e.status, DayStatus.halfDay);
      expect(e.workedMinutes, 240);
    });

    test('absent, weekly off and rejected', () {
      expect(eval(null).status, DayStatus.absent);
      expect(
        eval(null, day: DateTime(2026, 10, 18)).status,
        DayStatus.weeklyOff,
      );
      final rejected = record(
        'a',
        DateTime(2026, 10, 12, 9),
        outTime: DateTime(2026, 10, 12, 18),
        decision: ReviewDecision.rejected,
      );
      expect(eval(rejected).status, DayStatus.absent);
    });

    test('in progress today without checkout', () {
      final now = DateTime(2026, 10, 12, 12);
      final e = AttendanceRules.evaluate(
        record('a', DateTime(2026, 10, 12, 9)),
        dayShift,
        day: monday,
        now: now,
      );
      expect(e.status, DayStatus.inProgress);
    });
  });

  group('Shift', () {
    test('map round trip', () {
      final s = Shift.fromMap('day', dayShift.toMap());
      expect(s.startMinutes, dayShift.startMinutes);
      expect(s.endMinutes, dayShift.endMinutes);
      expect(s.workDays, dayShift.workDays);
      expect(s.timing, '09:00 – 18:00');
    });
  });

  group('AttendanceRecord', () {
    test('parses API json', () {
      final r = AttendanceRecord.fromMap('u_2026-10-12', {
        'uid': 'u',
        'employeeName': 'Asha',
        'date': '2026-10-12',
        'checkIn': {
          'time': DateTime(2026, 10, 12, 9).toUtc().toIso8601String(),
          'lat': 1,
          'lng': 2,
          'accuracy': 8,
          'flagReasons': ['face_mismatch'],
          'faceScore': 0.3,
        },
        'flagged': true,
        'reviewed': false,
      });
      expect(r.checkIn.time, DateTime(2026, 10, 12, 9));
      expect(r.checkIn.flagged, isTrue);
      expect(r.checkIn.faceScore, 0.3);
      expect(r.checkOut, isNull);
      expect(r.pendingReview, isTrue);
    });
  });

  group('ReportBuilder', () {
    const asha = AppUser(
      uid: 'asha',
      name: 'Asha',
      email: 'a@x.com',
      shiftId: 'day',
    );
    const ravi = AppUser(
      uid: 'ravi',
      name: 'Ravi',
      email: 'r@x.com',
      shiftId: 'day',
    );
    const boss = AppUser(
      uid: 'boss',
      name: 'Boss',
      email: 'b@x.com',
      role: UserRole.admin,
    );
    const gone = AppUser(
      uid: 'gone',
      name: 'Gone',
      email: 'g@x.com',
      active: false,
    );

    final records = [
      record(
        'asha',
        DateTime(2026, 10, 12, 9),
        outTime: DateTime(2026, 10, 12, 18),
      ),
      record(
        'asha',
        DateTime(2026, 10, 13, 9, 30),
        outTime: DateTime(2026, 10, 13, 18),
      ),
      record(
        'ravi',
        DateTime(2026, 10, 12, 9, 5),
        outTime: DateTime(2026, 10, 12, 18),
      ),
    ];

    List<ReportRow> build({String? uid}) => ReportBuilder.rows(
      employees: const [asha, ravi, boss, gone],
      records: records,
      shifts: const [dayShift],
      from: monday,
      to: DateTime(2026, 10, 18),
      now: later,
      employeeUid: uid,
    );

    test('one row per employee per day, admins & idle inactive excluded', () {
      final rows = build();
      expect(rows.length, 14); // 2 employees × 7 days
      expect(rows.any((r) => r.employee.uid == 'boss'), isFalse);
      expect(rows.any((r) => r.employee.uid == 'gone'), isFalse);
    });

    test('summary counts', () {
      final summary = {
        for (final s in ReportBuilder.summarize(build())) s.employee.uid: s,
      };
      final a = summary['asha']!;
      expect(a.present, 1);
      expect(a.late, 1);
      expect(a.absent, 3); // Wed–Fri
      expect(a.weeklyOff, 2);
      expect(a.attended, 2);
      expect(a.lateMinutes, 30);
      expect(summary['ravi']!.absent, 4);
    });

    test('employee filter and future days excluded', () {
      final rows = ReportBuilder.rows(
        employees: const [asha, ravi],
        records: records,
        shifts: const [dayShift],
        from: monday,
        to: DateTime(2026, 10, 31),
        now: DateTime(2026, 10, 13, 20),
        employeeUid: 'asha',
      );
      expect(rows.length, 2);
      expect(rows.first.day, DateTime(2026, 10, 13)); // newest first
    });

    test('csv export has header and one line per row', () {
      final rows = build(uid: 'asha');
      final text = utf8.decode(ReportExporter.csv(rows));
      final lines = text.trim().split(RegExp(r'\r?\n'));
      expect(lines.first, contains('Date'));
      expect(lines.length, rows.length + 1);
      expect(text, contains('2026-10-13'));
    });

    test('excel export produces a zip (xlsx) file', () {
      final rows = build();
      final bytes = ReportExporter.excel(rows, ReportBuilder.summarize(rows));
      expect(bytes.sublist(0, 2), [0x50, 0x4B]); // "PK"
    });
  });
}
