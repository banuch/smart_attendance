import 'package:intl/intl.dart';

final _dateKeyFormat = DateFormat('yyyy-MM-dd');

/// Calendar-day key (`yyyy-MM-dd`, local time) used for attendance documents.
String dateKey(DateTime d) => _dateKeyFormat.format(d);

DateTime parseDateKey(String key) => _dateKeyFormat.parse(key);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Every calendar day from [from] to [to], inclusive.
Iterable<DateTime> daysInRange(DateTime from, DateTime to) sync* {
  var d = dateOnly(from);
  final end = dateOnly(to);
  while (!d.isAfter(end)) {
    yield d;
    d = DateTime(d.year, d.month, d.day + 1);
  }
}

/// `HH:mm` → minutes since midnight.
int parseHm(String hm) {
  final parts = hm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Minutes since midnight → `HH:mm`.
String formatHm(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String formatDuration(int minutes) {
  if (minutes <= 0) return '0h 00m';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

final timeFormat = DateFormat('hh:mm a');
final dayFormat = DateFormat('EEE, d MMM yyyy');
