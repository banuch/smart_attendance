import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_shell.dart';
import 'core/app_config.dart';
import 'core/data/providers.dart';
import 'core/theme.dart';
import 'core/widgets/login_form.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${AppConfig.appName} Admin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const AdminGate(),
    );
  }
}

class AdminGate extends ConsumerWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.value == null) {
      return const Scaffold(
        body: LoginForm(
          title: '${AppConfig.appName} Admin',
          subtitle: 'Employer control panel',
        ),
      );
    }
    final profile = ref.watch(currentUserProvider);
    if (profile.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = profile.value;
    if (user == null || !user.isAdmin || !user.active) {
      return const BlockedScreen(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Admin access required',
        message:
            'This account is not an active admin. Use the mobile app to mark '
            'attendance, or ask an admin to grant access.',
      );
    }
    return const AdminShell();
  }
}
