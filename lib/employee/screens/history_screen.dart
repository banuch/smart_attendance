import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/attendance_record.dart';
import '../../core/theme.dart';
import '../../core/utils/attendance_rules.dart';
import '../../core/utils/dates.dart';
import '../employee_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;
    final records = ref.watch(myMonthProvider(_month));
    final shift = ref.watch(myShiftProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My attendance')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isCurrentMonth ? null : () => _shift(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: records.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (list) {
                final byDate = {for (final r in list) r.date: r};
                final last = isCurrentMonth
                    ? now
                    : DateTime(_month.year, _month.month + 1, 0);
                final days = daysInRange(_month, last).toList().reversed;
                final evals = [
                  for (final d in days)
                    (
                      day: d,
                      record: byDate[dateKey(d)],
                      eval: AttendanceRules.evaluate(
                        byDate[dateKey(d)],
                        shift,
                        day: d,
                      ),
                    ),
                ];
                int count(bool Function(DayStatus) test) =>
                    evals.where((e) => test(e.eval.status)).length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _Stat(
                            'Present',
                            count((s) => s.attended),
                            Colors.green,
                          ),
                          _Stat(
                            'Late',
                            count((s) => s == DayStatus.late),
                            Colors.orange,
                          ),
                          _Stat(
                            'Half day',
                            count((s) => s == DayStatus.halfDay),
                            Colors.deepOrange,
                          ),
                          _Stat(
                            'Absent',
                            count((s) => s == DayStatus.absent),
                            Colors.red,
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.separated(
                        itemCount: evals.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _DayTile(
                          day: evals[i].day,
                          record: evals[i].record,
                          eval: evals[i].eval,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: color),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.record, required this.eval});

  final DateTime day;
  final AttendanceRecord? record;
  final DayEvaluation eval;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor(eval.status).withValues(alpha: 0.15),
        child: Text(
          '${day.day}',
          style: TextStyle(color: statusColor(eval.status)),
        ),
      ),
      title: Text(DateFormat('EEEE').format(day)),
      subtitle: r == null
          ? null
          : Text(
              '${timeFormat.format(r.checkIn.time)} → '
              '${r.checkOut == null ? '--' : timeFormat.format(r.checkOut!.time)}'
              '${r.checkOut == null ? '' : ' · ${formatDuration(eval.workedMinutes)}'}',
            ),
      trailing: StatusChip(eval.status),
    );
  }
}
