import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/data/repositories.dart';
import '../../core/models/app_user.dart';
import '../../firebase_options.dart';

/// Creates employee logins from the browser without signing the admin out.
///
/// The client SDK signs in whoever it creates, so a second, throwaway
/// Firebase app instance is used for account creation.
class AdminUserService {
  AdminUserService(this._users);

  final UserRepository _users;

  static const _appName = 'user-admin';

  Future<FirebaseAuth> _secondaryAuth() async {
    final app = Firebase.apps.any((a) => a.name == _appName)
        ? Firebase.app(_appName)
        : await Firebase.initializeApp(
            name: _appName,
            options: DefaultFirebaseOptions.currentPlatform,
          );
    final auth = FirebaseAuth.instanceFor(app: app);
    if (kIsWeb) {
      await auth.setPersistence(Persistence.NONE);
    }
    return auth;
  }

  /// Creates the Auth account and the profile document. Returns the uid.
  Future<String> createEmployee(AppUser profile, String password) async {
    final auth = await _secondaryAuth();
    final cred = await auth.createUserWithEmailAndPassword(
      email: profile.email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    await auth.signOut();
    await _users.create(
      AppUser(
        uid: uid,
        name: profile.name,
        email: profile.email.trim(),
        phone: profile.phone,
        employeeCode: profile.employeeCode,
        role: profile.role,
        active: profile.active,
        siteIds: profile.siteIds,
        shiftId: profile.shiftId,
      ),
    );
    return uid;
  }

  Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email);
}
