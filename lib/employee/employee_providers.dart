import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/models/attendance_record.dart';
import '../core/models/shift.dart';
import '../core/models/site.dart';
import '../core/utils/dates.dart';
import 'services/device_service.dart';
import 'services/face_service.dart';
import 'services/location_service.dart';
import 'services/punch_service.dart';

final deviceIdentityProvider = FutureProvider<DeviceIdentity>(
  (ref) => DeviceService().identity(),
);

final locationServiceProvider = Provider((ref) => LocationService());

final faceServiceProvider = Provider<FaceService>((ref) {
  final service = FaceService();
  ref.onDispose(service.dispose);
  return service;
});

final punchServiceProvider = Provider(
  (ref) => PunchService(
    attendance: ref.watch(attendanceRepoProvider),
    users: ref.watch(userRepoProvider),
    storage: ref.watch(storageProvider),
  ),
);

/// Today's record for the signed-in employee.
final todayRecordProvider = StreamProvider<AttendanceRecord?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref
      .watch(attendanceRepoProvider)
      .watchDay(uid, dateKey(DateTime.now()));
});

/// Signed-in employee's records for a month (first day of month as key).
final myMonthProvider =
    StreamProvider.family<List<AttendanceRecord>, DateTime>((ref, month) {
      final uid = ref.watch(authStateProvider).value?.uid;
      if (uid == null) return Stream.value(const []);
      final from = DateTime(month.year, month.month);
      final to = DateTime(month.year, month.month + 1, 0);
      return ref
          .watch(attendanceRepoProvider)
          .watchUserRange(uid, dateKey(from), dateKey(to));
    });

final myShiftProvider = Provider<Shift?>((ref) {
  final shiftId = ref.watch(currentUserProvider).value?.shiftId;
  final shifts = ref.watch(shiftsProvider).value ?? const [];
  for (final s in shifts) {
    if (s.id == shiftId) return s;
  }
  return null;
});

final mySitesProvider = Provider<List<Site>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final sites = ref.watch(sitesProvider).value ?? const [];
  if (user == null) return const [];
  return PunchService.allowedSites(user, sites);
});
