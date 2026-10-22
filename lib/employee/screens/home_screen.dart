import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/models/attendance_record.dart';
import '../../core/theme.dart';
import '../../core/utils/attendance_rules.dart';
import '../../core/utils/dates.dart';
import '../employee_providers.dart';
import 'history_screen.dart';
import 'punch_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value!;
    final shift = ref.watch(myShiftProvider);
    final sites = ref.watch(mySitesProvider);
    final today = ref.watch(todayRecordProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Hello, ${user.name}', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(dayFormat.format(DateTime.now())),
            const SizedBox(height: 16),
            const _Clock(),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(shift?.name ?? 'No shift assigned'),
                    subtitle: shift == null ? null : Text(shift.timing),
                  ),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      sites.isEmpty
                          ? 'No work site configured'
                          : sites.map((s) => s.name).join(', '),
                    ),
                    subtitle: const Text('Allowed check-in location'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            today.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Could not load today: $e'),
              data: (record) => _TodayCard(record: record),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authStateProvider.notifier).signOut();
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.record});

  final AttendanceRecord? record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(myShiftProvider);
    final eval = AttendanceRules.evaluate(record, shift, day: DateTime.now());
    final r = record;
    final done = r?.checkOut != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  "Today's status",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (r != null) StatusChip(eval.status),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PunchInfo(
                    label: 'Check in',
                    punch: r?.checkIn,
                    icon: Icons.login,
                  ),
                ),
                Expanded(
                  child: _PunchInfo(
                    label: 'Check out',
                    punch: r?.checkOut,
                    icon: Icons.logout,
                  ),
                ),
              ],
            ),
            if (done) ...[
              const SizedBox(height: 12),
              Text(
                'Worked ${formatDuration(eval.workedMinutes)}',
                textAlign: TextAlign.center,
              ),
            ],
            if (r?.pendingReview ?? false) ...[
              const SizedBox(height: 12),
              const Text(
                'Sent to your admin for review.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 20),
            if (done)
              const FilledButton(
                onPressed: null,
                child: Text('Attendance complete for today'),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: r == null ? Colors.green : Colors.redAccent,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PunchScreen(today: r)),
                ),
                icon: Icon(r == null ? Icons.login : Icons.logout),
                label: Text(
                  r == null ? 'CHECK IN' : 'CHECK OUT',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PunchInfo extends StatelessWidget {
  const _PunchInfo({
    required this.label,
    required this.punch,
    required this.icon,
  });

  final String label;
  final Punch? punch;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = punch;
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(
          p == null ? '--:--' : timeFormat.format(p.time),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (p != null)
          Text(p.siteName, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    timeFormat.format(DateTime.now()),
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.displayMedium
        ?.copyWith(fontWeight: FontWeight.w300),
  );
}
