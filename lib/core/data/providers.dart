import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/shift.dart';
import '../models/site.dart';
import 'api_client.dart';
import 'repositories.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final userRepoProvider = Provider(
  (ref) => UserRepository(ref.watch(apiClientProvider)),
);
final siteRepoProvider = Provider(
  (ref) => SiteRepository(ref.watch(apiClientProvider)),
);
final shiftRepoProvider = Provider(
  (ref) => ShiftRepository(ref.watch(apiClientProvider)),
);
final attendanceRepoProvider = Provider(
  (ref) => AttendanceRepository(ref.watch(apiClientProvider)),
);

/// Sign-in state. The token is kept on the device between launches.
class AuthController extends AsyncNotifier<AuthSession?> {
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<AuthSession?> build() async {
    _api.onUnauthorized = () {
      _api.clearSession();
      state = const AsyncData(null);
    };
    return _api.restoreSession();
  }

  /// Throws [ApiException] with a message fit for the user.
  Future<void> signIn(String email, String password) async {
    final res = await _api.post('/api/auth/login', {
      'email': email,
      'password': password,
    });
    final uid = (res as Map)['user']['uid'] as String;
    await _api.saveSession(res['token'] as String, uid);
    state = AsyncData(AuthSession(uid));
  }

  Future<void> signOut() async {
    await _api.clearSession();
    state = const AsyncData(null);
  }
}

final authStateProvider = AsyncNotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);

/// Uid of the signed-in user. Data providers watch it so they restart (and
/// drop the previous user's data) when the account changes.
final sessionUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).value?.uid,
);

/// Profile of the signed-in user; null when signed out.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  if (ref.watch(sessionUidProvider) == null) return Stream.value(null);
  return ref.watch(userRepoProvider).watchMe();
});

final sitesProvider = StreamProvider<List<Site>>((ref) {
  if (ref.watch(sessionUidProvider) == null) return Stream.value(const []);
  return ref.watch(siteRepoProvider).watchAll();
});

final shiftsProvider = StreamProvider<List<Shift>>((ref) {
  if (ref.watch(sessionUidProvider) == null) return Stream.value(const []);
  return ref.watch(shiftRepoProvider).watchAll();
});

final employeesProvider = StreamProvider<List<AppUser>>((ref) {
  if (ref.watch(sessionUidProvider) == null) return Stream.value(const []);
  return ref.watch(userRepoProvider).watchAll();
});

/// All records with date keys in the inclusive range (admin).
final attendanceRangeProvider =
    StreamProvider.family<List<AttendanceRecord>, (String, String)>((
      ref,
      range,
    ) {
      if (ref.watch(sessionUidProvider) == null) return Stream.value(const []);
      return ref.watch(attendanceRepoProvider).watchRange(range.$1, range.$2);
    });

final pendingReviewProvider = StreamProvider<List<AttendanceRecord>>((ref) {
  if (ref.watch(sessionUidProvider) == null) return Stream.value(const []);
  return ref.watch(attendanceRepoProvider).watchPendingReview();
});
