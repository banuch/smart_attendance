import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/models/shift.dart';
import '../../core/theme.dart';
import '../../core/utils/dates.dart';
import '../widgets/common.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class ShiftsScreen extends ConsumerWidget {
  const ShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shifts = ref.watch(shiftsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ShiftFormDialog.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Add shift'),
      ),
      body: shifts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(Icons.error_outline, 'Could not load: $e'),
        data: (list) => list.isEmpty
            ? const EmptyState(
                Icons.schedule,
                'No shifts yet. Add one to enable late / half-day rules.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  for (final s in list)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.schedule),
                        title: Text('${s.name} · ${s.timing}'),
                        subtitle: Text(
                          'Grace ${s.graceMinutes} min · half day if later than '
                          '${s.halfDayAfterMinutes} min or worked under '
                          '${formatDuration(s.minFullDayMinutes)}\n'
                          'Work days: ${[for (final d in s.workDays) _weekdays[d - 1]].join(', ')}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () =>
                                  ShiftFormDialog.show(context, shift: s),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (await confirm(
                                  context,
                                  'Delete ${s.name}?',
                                  'Employees on this shift will have no late rules '
                                      'until reassigned.',
                                  action: 'Delete',
                                )) {
                                  await ref.read(shiftRepoProvider).delete(s.id);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class ShiftFormDialog extends ConsumerStatefulWidget {
  const ShiftFormDialog({super.key, this.shift});

  final Shift? shift;

  static Future<void> show(BuildContext context, {Shift? shift}) => showDialog(
    context: context,
    builder: (_) => ShiftFormDialog(shift: shift),
  );

  @override
  ConsumerState<ShiftFormDialog> createState() => _ShiftFormDialogState();
}

class _ShiftFormDialogState extends ConsumerState<ShiftFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.shift?.name);
  late int _start = widget.shift?.startMinutes ?? 9 * 60;
  late int _end = widget.shift?.endMinutes ?? 18 * 60;
  late final _grace = TextEditingController(
    text: '${widget.shift?.graceMinutes ?? 10}',
  );
  late final _halfDay = TextEditingController(
    text: '${widget.shift?.halfDayAfterMinutes ?? 120}',
  );
  late final _minHours = TextEditingController(
    text: ((widget.shift?.minFullDayMinutes ?? 360) / 60).toString(),
  );
  late final Set<int> _days = {
    ...(widget.shift?.workDays ?? const [1, 2, 3, 4, 5, 6]),
  };
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _grace, _halfDay, _minHours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t == null) return;
    setState(() {
      final m = t.hour * 60 + t.minute;
      start ? _start = m : _end = m;
    });
  }

  String? _intValidator(String? v) =>
      int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'Number' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_days.isEmpty) {
      showSnack(context, 'Pick at least one work day', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(shiftRepoProvider).save(
        Shift(
          id: widget.shift?.id ?? '',
          name: _name.text.trim(),
          startMinutes: _start,
          endMinutes: _end,
          graceMinutes: int.parse(_grace.text),
          halfDayAfterMinutes: int.parse(_halfDay.text),
          minFullDayMinutes: (double.parse(_minHours.text) * 60).round(),
          workDays: _days.toList()..sort(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text(widget.shift == null ? 'Add shift' : 'Edit shift'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Shift name *'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
                gap,
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(true),
                        icon: const Icon(Icons.login),
                        label: Text('Start ${formatHm(_start)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(false),
                        icon: const Icon(Icons.logout),
                        label: Text('End ${formatHm(_end)}'),
                      ),
                    ),
                  ],
                ),
                gap,
                TextFormField(
                  controller: _grace,
                  decoration: const InputDecoration(
                    labelText: 'Grace period (minutes)',
                    helperText: 'Check-in up to this late still counts as on time.',
                  ),
                  validator: _intValidator,
                ),
                gap,
                TextFormField(
                  controller: _halfDay,
                  decoration: const InputDecoration(
                    labelText: 'Half day if late by more than (minutes)',
                  ),
                  validator: _intValidator,
                ),
                gap,
                TextFormField(
                  controller: _minHours,
                  decoration: const InputDecoration(
                    labelText: 'Minimum hours for a full day',
                    helperText: 'Fewer worked hours (in → out) counts as half day.',
                  ),
                  validator: (v) =>
                      double.tryParse(v ?? '') == null ? 'Number' : null,
                ),
                gap,
                Text('Work days', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(_weekdays[d - 1]),
                        selected: _days.contains(d),
                        onSelected: (v) =>
                            setState(() => v ? _days.add(d) : _days.remove(d)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
