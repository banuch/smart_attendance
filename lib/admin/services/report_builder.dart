import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/models/shift.dart';
import '../../core/utils/attendance_rules.dart';
import '../../core/utils/dates.dart';

/// One employee on one day.
class ReportRow {
  const ReportRow({
    required this.employee,
    required this.day,
    required this.record,
    required this.shift,
    required this.eval,
  });

  final AppUser employee;
  final DateTime day;
  final AttendanceRecord? record;
  final Shift? shift;
  final DayEvaluation eval;
}

class EmployeeSummary {
  EmployeeSummary(this.employee);

  final AppUser employee;
  int present = 0;
  int late = 0;
  int halfDay = 0;
  int absent = 0;
  int weeklyOff = 0;
  int workedMinutes = 0;
  int lateMinutes = 0;
  int flagged = 0;

  /// Days attended in any form (present, late, half day, in progress).
  int get attended => present + late + halfDay;
}

/// Joins employees, shifts and attendance records into day rows.
class ReportBuilder {
  ReportBuilder._();

  /// Rows for every employee for every day in [from]..[to], excluding days
  /// after [now]. Admin accounts are excluded; inactive employees are included
  /// only for days they have a record.
  static List<ReportRow> rows({
    required List<AppUser> employees,
    required List<AttendanceRecord> records,
    required List<Shift> shifts,
    required DateTime from,
    required DateTime to,
    DateTime? now,
    String? employeeUid,
  }) {
    now ??= DateTime.now();
    final last = to.isAfter(now) ? now : to;
    final shiftById = {for (final s in shifts) s.id: s};
    final recordByKey = {for (final r in records) r.id: r};

    final rows = <ReportRow>[];
    for (final e in employees) {
      if (e.isAdmin) continue;
      if (employeeUid != null && e.uid != employeeUid) continue;
      for (final day in daysInRange(from, last)) {
        final record = recordByKey[AttendanceRecord.docId(e.uid, dateKey(day))];
        if (!e.active && record == null) continue;
        final shift = shiftById[record?.shiftId ?? e.shiftId] ?? shiftById[e.shiftId];
        rows.add(
          ReportRow(
            employee: e,
            day: day,
            record: record,
            shift: shift,
            eval: AttendanceRules.evaluate(record, shift, day: day, now: now),
          ),
        );
      }
    }
    rows.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : a.employee.name.compareTo(b.employee.name);
    });
    return rows;
  }

  static List<EmployeeSummary> summarize(List<ReportRow> rows) {
    final byUid = <String, EmployeeSummary>{};
    for (final row in rows) {
      final s = byUid.putIfAbsent(
        row.employee.uid,
        () => EmployeeSummary(row.employee),
      );
      switch (row.eval.status) {
        case DayStatus.present:
        case DayStatus.inProgress:
          s.present++;
        case DayStatus.late:
          s.late++;
        case DayStatus.halfDay:
          s.halfDay++;
        case DayStatus.absent:
          s.absent++;
        case DayStatus.weeklyOff:
          s.weeklyOff++;
      }
      s.workedMinutes += row.eval.workedMinutes;
      s.lateMinutes += row.eval.lateMinutes;
      if (row.record?.flagged ?? false) s.flagged++;
    }
    final list = byUid.values.toList()
      ..sort((a, b) => a.employee.name.compareTo(b.employee.name));
    return list;
  }
}
