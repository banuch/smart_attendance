import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../core/data/providers.dart';
import '../core/models/app_user.dart';
import '../core/widgets/login_form.dart';
import 'employee_providers.dart';
import 'screens/enroll_face_screen.dart';
import 'screens/home_screen.dart';

/// Routes the employee through: sign-in → active check → device binding →
/// face enrollment → home.
class EmployeeGate extends ConsumerWidget {
  const EmployeeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) return const _Loading();
    if (auth.value == null) {
      return const Scaffold(
        body: SafeArea(
          child: LoginForm(
            title: AppConfig.appName,
            subtitle: 'Sign in with the account your employer created.',
          ),
        ),
      );
    }

    final profile = ref.watch(currentUserProvider);
    final device = ref.watch(deviceIdentityProvider);
    if (profile.hasError) {
      return BlockedScreen(
        icon: Icons.cloud_off,
        title: 'Could not load your profile',
        message: '${profile.error}',
      );
    }
    final user = profile.value;
    if (profile.isLoading || device.isLoading) return const _Loading();
    if (user == null) {
      return const BlockedScreen(
        icon: Icons.person_off,
        title: 'No employee profile',
        message: 'Your account is not set up yet. Contact your admin.',
      );
    }
    if (!user.active) {
      return const BlockedScreen(
        icon: Icons.block,
        title: 'Account deactivated',
        message: 'Your account has been deactivated. Contact your admin.',
      );
    }

    final identity = device.value!;
    if (user.deviceId == null) {
      return _BindDevice(
        user: user,
        deviceId: identity.id,
        model: identity.model,
      );
    }
    if (user.deviceId != identity.id) {
      return BlockedScreen(
        icon: Icons.phonelink_lock,
        title: 'Registered to another phone',
        message:
            'Your account is linked to ${user.deviceModel ?? 'another device'}. '
            'Ask your admin to reset your device to use this phone.',
      );
    }
    if (!user.faceEnrolled) return EnrollFaceScreen(user: user);
    return const HomeScreen();
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Binds the account to this device on first login, then rebuilds the gate.
class _BindDevice extends ConsumerStatefulWidget {
  const _BindDevice({
    required this.user,
    required this.deviceId,
    required this.model,
  });

  final AppUser user;
  final String deviceId;
  final String model;

  @override
  ConsumerState<_BindDevice> createState() => _BindDeviceState();
}

class _BindDeviceState extends ConsumerState<_BindDevice> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  Future<void> _bind() async {
    setState(() => _error = null);
    try {
      await ref
          .read(userRepoProvider)
          .bindDevice(widget.deviceId, widget.model);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error == null) return const _Loading();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not register this device.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _bind, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
