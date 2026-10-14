import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/data/providers.dart';
import '../../core/theme.dart';
import '../../core/utils/attendance_rules.dart';
import '../../core/utils/dates.dart';
import '../services/report_builder.dart';
import '../widgets/attendance_detail_dialog.dart';
import '../widgets/common.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final weekStart = dateOnly(now).subtract(const Duration(days: 6));
    final records = ref.watch(
      attendanceRangeProvider((dateKey(weekStart), dateKey(now))),
    );
    final employees = ref.watch(employeesProvider);
    final shifts = ref.watch(shiftsProvider);
    final sites = ref.watch(sitesProvider).value ?? const [];
    final pending = ref.watch(pendingReviewProvider).value?.length ?? 0;

    if (records.hasError) {
      return EmptyState(Icons.error_outline, 'Could not load: ${records.error}');
    }
    if (!records.hasValue || !employees.hasValue || !shifts.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final week = ReportBuilder.rows(
      employees: employees.value!,
      records: records.value!,
      shifts: shifts.value!,
      from: weekStart,
      to: now,
      now: now,
    );
    final today = week.where((r) => dateKey(r.day) == dateKey(now)).toList();
    int count(bool Function(DayStatus) test) =>
        today.where((r) => test(r.eval.status)).length;
    final scheduled = today.where((r) => r.eval.status != DayStatus.weeklyOff);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1100;
        final stats = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in [
              StatCard(
                label: 'Present today',
                value: '${count((s) => s.attended)} / ${scheduled.length}',
                icon: Icons.how_to_reg,
                color: Colors.green,
              ),
              StatCard(
                label: 'Late',
                value: '${count((s) => s == DayStatus.late)}',
                icon: Icons.timer_outlined,
                color: Colors.orange,
              ),
              StatCard(
                label: 'Absent',
                value: '${count((s) => s == DayStatus.absent)}',
                icon: Icons.person_off_outlined,
                color: Colors.red,
              ),
              StatCard(
                label: 'Pending review',
                value: '$pending',
                icon: Icons.flag_outlined,
                color: Colors.deepPurple,
              ),
            ])
              SizedBox(width: 240, child: s),
          ],
        );

        final table = Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Today · ${dayFormat.format(now)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (today.isEmpty)
                const EmptyState(Icons.people_outline, 'No employees yet.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('Employee')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('In')),
                      DataColumn(label: Text('Out')),
                      DataColumn(label: Text('Site')),
                      DataColumn(label: Text('Selfie')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final r in today)
                        DataRow(
                          onSelectChanged: r.record == null
                              ? null
                              : (_) => AttendanceDetailDialog.show(
                                  context,
                                  r.record!,
                                ),
                          cells: [
                            DataCell(Text(r.employee.name)),
                            DataCell(StatusChip(r.eval.status)),
                            DataCell(
                              Text(
                                r.record == null
                                    ? '-'
                                    : timeFormat.format(r.record!.checkIn.time),
                              ),
                            ),
                            DataCell(
                              Text(
                                r.record?.checkOut == null
                                    ? '-'
                                    : timeFormat.format(r.record!.checkOut!.time),
                              ),
                            ),
                            DataCell(Text(r.record?.checkIn.siteName ?? '-')),
                            DataCell(SelfieThumb(r.record?.checkIn.photoUrl)),
                            DataCell(
                              (r.record?.pendingReview ?? false)
                                  ? const Tooltip(
                                      message: 'Needs review',
                                      child: Icon(Icons.flag, color: Colors.orange),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );

        final map = Card(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 360,
            child: SiteMap(
              sites: sites,
              pins: [
                for (final r in today)
                  if (r.record != null)
                    MapPin(
                      LatLng(r.record!.checkIn.lat, r.record!.checkIn.lng),
                      '${r.employee.name} · ${timeFormat.format(r.record!.checkIn.time)}',
                      color: r.record!.flagged ? Colors.orange : Colors.green,
                    ),
              ],
            ),
          ),
        );

        final chart = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance · last 7 days',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(height: 220, child: _WeekChart(rows: week, from: weekStart)),
              ],
            ),
          ),
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            stats,
            const SizedBox(height: 16),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: table),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [map, const SizedBox(height: 16), chart],
                    ),
                  ),
                ],
              )
            else ...[
              table,
              const SizedBox(height: 16),
              map,
              const SizedBox(height: 16),
              chart,
            ],
          ],
        );
      },
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.rows, required this.from});

  final List<ReportRow> rows;
  final DateTime from;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) from.add(Duration(days: i))];
    final groups = <BarChartGroupData>[];
    var maxY = 1.0;
    for (var i = 0; i < days.length; i++) {
      final key = dateKey(days[i]);
      final dayRows = rows.where((r) => dateKey(r.day) == key);
      final onTime = dayRows
          .where(
            (r) =>
                r.eval.status == DayStatus.present ||
                r.eval.status == DayStatus.inProgress,
          )
          .length
          .toDouble();
      final late = dayRows
          .where(
            (r) =>
                r.eval.status == DayStatus.late ||
                r.eval.status == DayStatus.halfDay,
          )
          .length
          .toDouble();
      final absent = dayRows
          .where((r) => r.eval.status == DayStatus.absent)
          .length
          .toDouble();
      final total = onTime + late + absent;
      if (total > maxY) maxY = total;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: total,
              width: 22,
              borderRadius: BorderRadius.circular(4),
              rodStackItems: [
                BarChartRodStackItem(0, onTime, Colors.green),
                BarChartRodStackItem(onTime, onTime + late, Colors.orange),
                BarChartRodStackItem(onTime + late, total, Colors.red.shade300),
              ],
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: maxY,
        barGroups: groups,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(DateFormat('E').format(days[v.toInt()])),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
