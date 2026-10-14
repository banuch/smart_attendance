import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/data/providers.dart';
import 'screens/dashboard_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/review_screen.dart';
import 'screens/shifts_screen.dart';
import 'screens/sites_screen.dart';

class _Page {
  const _Page(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final Widget Function() builder;
}

final _pages = [
  _Page('Dashboard', Icons.dashboard_outlined, () => const DashboardScreen()),
  _Page('Review', Icons.flag_outlined, () => const ReviewScreen()),
  _Page('Employees', Icons.people_outline, () => const EmployeesScreen()),
  _Page('Sites', Icons.location_city_outlined, () => const SitesScreen()),
  _Page('Shifts', Icons.schedule_outlined, () => const ShiftsScreen()),
  _Page('Reports', Icons.assessment_outlined, () => const ReportsScreen()),
];

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  Widget _icon(int i) {
    final page = _pages[i];
    if (page.label != 'Review') return Icon(page.icon);
    final pending = ref.watch(pendingReviewProvider).value?.length ?? 0;
    return Badge(
      isLabelVisible: pending > 0,
      label: Text('$pending'),
      child: Icon(page.icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final user = ref.watch(currentUserProvider).value;
    final page = _pages[_index];

    final appBar = AppBar(
      title: Text(page.label),
      actions: [
        if (user != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text(user.name)),
          ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
      ],
    );

    final body = KeyedSubtree(key: ValueKey(_index), child: page.builder());

    if (!wide) {
      return Scaffold(
        appBar: appBar,
        drawer: NavigationDrawer(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            Navigator.pop(context);
          },
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
              child: Text(AppConfig.appName),
            ),
            for (var i = 0; i < _pages.length; i++)
              NavigationDrawerDestination(
                icon: _icon(i),
                label: Text(_pages[i].label),
              ),
          ],
        ),
        body: body,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Icon(
                Icons.fingerprint,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            destinations: [
              for (var i = 0; i < _pages.length; i++)
                NavigationRailDestination(
                  icon: _icon(i),
                  label: Text(_pages[i].label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(appBar: appBar, body: body),
          ),
        ],
      ),
    );
  }
}
