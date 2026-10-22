import '../utils/dates.dart';

class Shift {
  const Shift({
    required this.id,
    required this.name,
    required this.startMinutes,
    required this.endMinutes,
    this.graceMinutes = 10,
    this.halfDayAfterMinutes = 120,
    this.minFullDayMinutes = 360,
    this.workDays = const [1, 2, 3, 4, 5, 6],
  });

  final String id;
  final String name;

  /// Shift start / end as minutes since midnight (local time).
  final int startMinutes;
  final int endMinutes;

  /// Arriving up to this many minutes after start still counts as on time.
  final int graceMinutes;

  /// Arriving more than this many minutes after start counts as a half day.
  final int halfDayAfterMinutes;

  /// Working fewer minutes than this (check-in to check-out) is a half day.
  final int minFullDayMinutes;

  /// ISO weekdays (1 = Monday … 7 = Sunday) on which the shift is worked.
  final List<int> workDays;

  String get timing => '${formatHm(startMinutes)} – ${formatHm(endMinutes)}';

  bool isWorkDay(DateTime d) => workDays.contains(d.weekday);

  factory Shift.fromMap(String id, Map<String, dynamic> m) => Shift(
    id: id,
    name: m['name'] as String? ?? '',
    startMinutes: parseHm(m['start'] as String? ?? '09:00'),
    endMinutes: parseHm(m['end'] as String? ?? '18:00'),
    graceMinutes: (m['graceMinutes'] as num?)?.toInt() ?? 10,
    halfDayAfterMinutes: (m['halfDayAfterMinutes'] as num?)?.toInt() ?? 120,
    minFullDayMinutes: (m['minFullDayMinutes'] as num?)?.toInt() ?? 360,
    workDays:
        (m['workDays'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [1, 2, 3, 4, 5, 6],
  );

  factory Shift.fromJson(Map<String, dynamic> m) =>
      Shift.fromMap(m['id'] as String, m);

  Map<String, dynamic> toMap() => {
    'name': name,
    'start': formatHm(startMinutes),
    'end': formatHm(endMinutes),
    'graceMinutes': graceMinutes,
    'halfDayAfterMinutes': halfDayAfterMinutes,
    'minFullDayMinutes': minFullDayMinutes,
    'workDays': workDays,
  };
}
