import '../models/attendance_record.dart';
import '../models/shift.dart';
import 'dates.dart';

enum DayStatus { present, late, halfDay, absent, weeklyOff, inProgress }

extension DayStatusLabel on DayStatus {
  String get label => switch (this) {
    DayStatus.present => 'Present',
    DayStatus.late => 'Late',
    DayStatus.halfDay => 'Half day',
    DayStatus.absent => 'Absent',
    DayStatus.weeklyOff => 'Weekly off',
    DayStatus.inProgress => 'Checked in',
  };

  /// Counts towards "present" totals (attended in some form).
  bool get attended =>
      this == DayStatus.present ||
      this == DayStatus.late ||
      this == DayStatus.halfDay ||
      this == DayStatus.inProgress;
}

class DayEvaluation {
  const DayEvaluation({
    required this.status,
    this.lateMinutes = 0,
    this.workedMinutes = 0,
  });

  final DayStatus status;
  final int lateMinutes;
  final int workedMinutes;
}

/// Derives status from stored punch times and the shift rules.
///
/// Status is never stored: it is computed from server timestamps on read, so a
/// tampered phone clock cannot change it and editing a shift re-evaluates it.
class AttendanceRules {
  AttendanceRules._();

  static DayEvaluation evaluate(
    AttendanceRecord? record,
    Shift? shift, {
    required DateTime day,
    DateTime? now,
  }) {
    now ??= DateTime.now();
    if (record == null || record.rejected) {
      if (shift != null && !shift.isWorkDay(day)) {
        return const DayEvaluation(status: DayStatus.weeklyOff);
      }
      return const DayEvaluation(status: DayStatus.absent);
    }

    final checkIn = record.checkIn.time;
    final checkOut = record.checkOut?.time;
    final worked = checkOut == null
        ? 0
        : checkOut.difference(checkIn).inMinutes.clamp(0, 24 * 60);

    if (shift == null) {
      return DayEvaluation(
        status: checkOut == null && _isSameDay(day, now)
            ? DayStatus.inProgress
            : DayStatus.present,
        workedMinutes: worked,
      );
    }

    final shiftStart = dateOnly(day).add(Duration(minutes: shift.startMinutes));
    final late = checkIn.difference(shiftStart).inMinutes;
    final lateMinutes = late > shift.graceMinutes ? late : 0;

    DayStatus status;
    if (late > shift.halfDayAfterMinutes) {
      status = DayStatus.halfDay;
    } else if (late > shift.graceMinutes) {
      status = DayStatus.late;
    } else {
      status = DayStatus.present;
    }

    if (checkOut != null) {
      if (worked < shift.minFullDayMinutes) status = DayStatus.halfDay;
    } else if (_isSameDay(day, now) && status != DayStatus.halfDay) {
      // Still at work today: show as in progress, keep "late" visible.
      if (status == DayStatus.present) status = DayStatus.inProgress;
    }

    return DayEvaluation(
      status: status,
      lateMinutes: lateMinutes,
      workedMinutes: worked,
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
