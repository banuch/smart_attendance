import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/models/shift.dart';
import '../../core/models/site.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  String _query = '';
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider);
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => EmployeeFormDialog.show(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add employee'),
      ),
      body: employees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(Icons.error_outline, 'Could not load: $e'),
        data: (all) {
          final q = _query.toLowerCase();
          final list = all
              .where((e) => _showInactive || e.active)
              .where(
                (e) =>
                    q.isEmpty ||
                    e.name.toLowerCase().contains(q) ||
                    e.email.toLowerCase().contains(q) ||
                    e.employeeCode.toLowerCase().contains(q),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search name, email or code',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilterChip(
                    label: const Text('Show inactive'),
                    selected: _showInactive,
                    onSelected: (v) => setState(() => _showInactive = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                const EmptyState(Icons.people_outline, 'No employees found.')
              else
                Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Code')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Role')),
                        DataColumn(label: Text('Shift')),
                        DataColumn(label: Text('Sites')),
                        DataColumn(label: Text('Device')),
                        DataColumn(label: Text('Face')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final e in list)
                          DataRow(
                            cells: [
                              DataCell(Text(e.name)),
                              DataCell(Text(e.employeeCode)),
                              DataCell(Text(e.email)),
                              DataCell(Text(e.isAdmin ? 'Admin' : 'Employee')),
                              DataCell(
                                Text(
                                  shifts
                                          .where((s) => s.id == e.shiftId)
                                          .firstOrNull
                                          ?.name ??
                                      '-',
                                ),
                              ),
                              DataCell(
                                Text(
                                  e.siteIds.isEmpty
                                      ? 'Any'
                                      : sites
                                            .where(
                                              (s) => e.siteIds.contains(s.id),
                                            )
                                            .map((s) => s.name)
                                            .join(', '),
                                ),
                              ),
                              DataCell(Text(e.deviceModel ?? 'Not linked')),
                              DataCell(
                                e.faceEnrolled
                                    ? SelfieThumb(e.faceUrl, size: 32)
                                    : const Text('Not enrolled'),
                              ),
                              DataCell(
                                Text(
                                  e.active ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    color: e.active
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              DataCell(_EmployeeActions(employee: e)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmployeeActions extends ConsumerWidget {
  const _EmployeeActions({required this.employee});

  final AppUser employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.read(userRepoProvider);
    Future<void> run(String done, Future<void> Function() action) async {
      try {
        await action();
        if (context.mounted) showSnack(context, done);
      } catch (e) {
        if (context.mounted) showSnack(context, 'Failed: $e', error: true);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => EmployeeFormDialog.show(context, employee: employee),
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'device':
                if (await confirm(
                  context,
                  'Reset device?',
                  '${employee.name} will be able to sign in from a new phone. '
                      'The next phone they sign in on becomes their device.',
                  action: 'Reset',
                )) {
                  await run(
                    'Device reset',
                    () => users.resetDevice(employee.uid),
                  );
                }
              case 'face':
                if (context.mounted &&
                    await confirm(
                      context,
                      'Reset face?',
                      '${employee.name} will be asked to register their face '
                          'again on next app launch.',
                      action: 'Reset',
                    )) {
                  await run('Face reset', () => users.resetFace(employee.uid));
                }
              case 'password':
                if (context.mounted) {
                  await SetPasswordDialog.show(context, employee: employee);
                }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'device',
              enabled: employee.deviceId != null,
              child: const Text('Reset device'),
            ),
            PopupMenuItem(
              value: 'face',
              enabled: employee.faceEnrolled,
              child: const Text('Reset face'),
            ),
            const PopupMenuItem(
              value: 'password',
              child: Text('Set new password'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Create / edit employee profile.
class EmployeeFormDialog extends ConsumerStatefulWidget {
  const EmployeeFormDialog({super.key, this.employee});

  final AppUser? employee;

  static Future<void> show(BuildContext context, {AppUser? employee}) =>
      showDialog(
        context: context,
        builder: (_) => EmployeeFormDialog(employee: employee),
      );

  @override
  ConsumerState<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends ConsumerState<EmployeeFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee?.name);
  late final _email = TextEditingController(text: widget.employee?.email);
  late final _phone = TextEditingController(text: widget.employee?.phone);
  late final _code = TextEditingController(text: widget.employee?.employeeCode);
  final _password = TextEditingController();
  late UserRole _role = widget.employee?.role ?? UserRole.employee;
  late String? _shiftId = widget.employee?.shiftId;
  late final Set<String> _siteIds = {...?widget.employee?.siteIds};
  late bool _active = widget.employee?.active ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.employee == null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _code, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final profile = AppUser(
      uid: widget.employee?.uid ?? '',
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      employeeCode: _code.text.trim(),
      role: _role,
      active: _active,
      siteIds: _siteIds.toList(),
      shiftId: _shiftId,
    );
    try {
      if (_isNew) {
        await ref.read(userRepoProvider).create(profile, _password.text);
      } else {
        await ref.read(userRepoProvider).updateProfile(profile);
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, _isNew ? 'Employee created' : 'Employee updated');
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];
    const gap = SizedBox(height: 12);

    return AlertDialog(
      title: Text(_isNew ? 'Add employee' : 'Edit employee'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                ),
                gap,
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                          labelText: 'Employee code',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                  ],
                ),
                gap,
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (login) *',
                  ),
                  validator: (v) =>
                      v!.contains('@') ? null : 'Enter a valid email',
                ),
                if (_isNew) ...[
                  gap,
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'Initial password *',
                      helperText: 'Share with the employee. You can set a new one later.',
                    ),
                    validator: (v) =>
                        v!.length < 8 ? 'Minimum 8 characters' : null,
                  ),
                ],
                gap,
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<UserRole>(
                        initialValue: _role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                            value: UserRole.employee,
                            child: Text('Employee'),
                          ),
                          DropdownMenuItem(
                            value: UserRole.admin,
                            child: Text('Admin'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _role = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: shifts.any((s) => s.id == _shiftId)
                            ? _shiftId
                            : null,
                        decoration: const InputDecoration(labelText: 'Shift'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final s in shifts)
                            DropdownMenuItem(
                              value: s.id,
                              child: Text('${s.name} (${s.timing})'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _shiftId = v),
                      ),
                    ),
                  ],
                ),
                gap,
                Text(
                  'Allowed sites',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                if (sites.isEmpty)
                  const Text('No sites yet. Add one under Sites.')
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in sites)
                        FilterChip(
                          label: Text(s.name),
                          selected: _siteIds.contains(s.id),
                          onSelected: (v) => setState(
                            () =>
                                v ? _siteIds.add(s.id) : _siteIds.remove(s.id),
                          ),
                        ),
                    ],
                  ),
                Text(
                  'None selected = may check in at any site.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                gap,
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Inactive accounts cannot mark attendance.',
                  ),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Admin sets a new password; the employee is signed out everywhere.
class SetPasswordDialog extends ConsumerStatefulWidget {
  const SetPasswordDialog({super.key, required this.employee});

  final AppUser employee;

  static Future<void> show(BuildContext context, {required AppUser employee}) =>
      showDialog(
        context: context,
        builder: (_) => SetPasswordDialog(employee: employee),
      );

  @override
  ConsumerState<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<SetPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepoProvider)
          .setPassword(widget.employee.uid, _password.text);
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Password changed for ${widget.employee.name}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New password for ${widget.employee.name}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _password,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'They will be signed out on every device.',
                ),
                validator: (v) => v!.length < 8 ? 'Minimum 8 characters' : null,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Set password'),
        ),
      ],
    );
  }
}
