import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme.dart';
import '../../core/utils/dates.dart';
import '../services/report_builder.dart';
import '../services/report_exporter.dart';
import '../widgets/attendance_detail_dialog.dart';
import '../widgets/common.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTimeRange _range = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month),
    end: dateOnly(DateTime.now()),
  );
  String? _employeeUid;
  bool _showDetail = false;
  bool _exporting = false;

  static final _short = DateFormat('d MMM yyyy');

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: dateOnly(DateTime.now()),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _preset(DateTimeRange r) => setState(() => _range = r);

  Future<void> _export(
    ExportFormat format,
    List<ReportRow> rows,
    List<EmployeeSummary> summary,
  ) async {
    setState(() => _exporting = true);
    try {
      final from = dateKey(_range.start);
      final to = dateKey(_range.end);
      await ReportExporter.download(
        format,
        rows,
        summary,
        baseName: 'attendance_${from}_to_$to',
        title:
            'Attendance report · ${_short.format(_range.start)} – '
            '${_short.format(_range.end)}',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final records = ref.watch(
      attendanceRangeProvider((dateKey(_range.start), dateKey(_range.end))),
    );
    final employees = ref.watch(employeesProvider);
    final shifts = ref.watch(shiftsProvider);

    final staff = (employees.value ?? const <AppUser>[])
        .where((e) => !e.isAdmin)
        .toList();

    final filters = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range),
          label: Text(
            '${_short.format(_range.start)} – ${_short.format(_range.end)}',
          ),
        ),
        ActionChip(
          label: const Text('This month'),
          onPressed: () => _preset(
            DateTimeRange(start: DateTime(now.year, now.month), end: dateOnly(now)),
          ),
        ),
        ActionChip(
          label: const Text('Last month'),
          onPressed: () => _preset(
            DateTimeRange(
              start: DateTime(now.year, now.month - 1),
              end: DateTime(now.year, now.month, 0),
            ),
          ),
        ),
        ActionChip(
          label: const Text('Last 7 days'),
          onPressed: () => _preset(
            DateTimeRange(
              start: dateOnly(now).subtract(const Duration(days: 6)),
              end: dateOnly(now),
            ),
          ),
        ),
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String?>(
            initialValue: _employeeUid,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Employee',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All employees')),
              for (final e in staff)
                DropdownMenuItem(value: e.uid, child: Text(e.name)),
            ],
            onChanged: (v) => setState(() => _employeeUid = v),
          ),
        ),
      ],
    );

    if (records.hasError) {
      return EmptyState(Icons.error_outline, 'Could not load: ${records.error}');
    }
    if (!records.hasValue || !employees.hasValue || !shifts.hasValue) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          filters,
          const SizedBox(height: 48),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final rows = ReportBuilder.rows(
      employees: employees.value!,
      records: records.value!,
      shifts: shifts.value!,
      from: _range.start,
      to: _range.end,
      now: now,
      employeeUid: _employeeUid,
    );
    final summary = ReportBuilder.summarize(rows);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        filters,
        const SizedBox(height: 16),
        Row(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Summary')),
                ButtonSegment(value: true, label: Text('Daily detail')),
              ],
              selected: {_showDetail},
              onSelectionChanged: (s) => setState(() => _showDetail = s.first),
            ),
            const Spacer(),
            if (_exporting)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            MenuAnchor(
              builder: (context, controller, _) => FilledButton.icon(
                onPressed: rows.isEmpty || _exporting
                    ? null
                    : () => controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.download),
                label: const Text('Export'),
              ),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.table_chart_outlined),
                  onPressed: () => _export(ExportFormat.excel, rows, summary),
                  child: const Text('Excel (.xlsx)'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.description_outlined),
                  onPressed: () => _export(ExportFormat.csv, rows, summary),
                  child: const Text('CSV'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => _export(ExportFormat.pdf, rows, summary),
                  child: const Text('PDF'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const EmptyState(Icons.assessment_outlined, 'No data for this range.')
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _showDetail ? _detailTable(rows) : _summaryTable(summary),
            ),
          ),
      ],
    );
  }

  Widget _summaryTable(List<EmployeeSummary> summary) => DataTable(
    columns: [
      for (final h in ReportExporter.summaryHeader)
        DataColumn(label: Text(h), numeric: h != 'Employee' && h != 'Code'),
    ],
    rows: [
      for (final s in summary)
        DataRow(
          cells: [
            for (final v in ReportExporter.summaryRow(s)) DataCell(Text('$v')),
          ],
        ),
    ],
  );

  Widget _detailTable(List<ReportRow> rows) => DataTable(
    showCheckboxColumn: false,
    columns: const [
      DataColumn(label: Text('Date')),
      DataColumn(label: Text('Employee')),
      DataColumn(label: Text('Status')),
      DataColumn(label: Text('In')),
      DataColumn(label: Text('Out')),
      DataColumn(label: Text('Worked')),
      DataColumn(label: Text('Late'), numeric: true),
      DataColumn(label: Text('Site')),
      DataColumn(label: Text('')),
    ],
    rows: [
      for (final r in rows)
        DataRow(
          onSelectChanged: r.record == null
              ? null
              : (_) => AttendanceDetailDialog.show(context, r.record!),
          cells: [
            DataCell(Text(DateFormat('EEE d MMM').format(r.day))),
            DataCell(Text(r.employee.name)),
            DataCell(StatusChip(r.eval.status)),
            DataCell(
              Text(r.record == null ? '-' : timeFormat.format(r.record!.checkIn.time)),
            ),
            DataCell(
              Text(
                r.record?.checkOut == null
                    ? '-'
                    : timeFormat.format(r.record!.checkOut!.time),
              ),
            ),
            DataCell(
              Text(r.eval.workedMinutes == 0 ? '-' : formatDuration(r.eval.workedMinutes)),
            ),
            DataCell(Text(r.eval.lateMinutes == 0 ? '-' : '${r.eval.lateMinutes}m')),
            DataCell(Text(r.record?.checkIn.siteName ?? '-')),
            DataCell(
              (r.record?.flagged ?? false)
                  ? Icon(
                      Icons.flag,
                      color: r.record!.reviewed ? Colors.grey : Colors.orange,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
    ],
  );
}
