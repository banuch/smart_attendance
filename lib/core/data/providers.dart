import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/shift.dart';
import '../models/site.dart';
import 'repositories.dart';

final authProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
final storageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final userRepoProvider = Provider(
  (ref) => UserRepository(ref.watch(firestoreProvider)),
);
final siteRepoProvider = Provider(
  (ref) => SiteRepository(ref.watch(firestoreProvider)),
);
final shiftRepoProvider = Provider(
  (ref) => ShiftRepository(ref.watch(firestoreProvider)),
);
final attendanceRepoProvider = Provider(
  (ref) => AttendanceRepository(ref.watch(firestoreProvider)),
);

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authProvider).authStateChanges(),
);

/// Profile of the signed-in user; null when signed out or no profile exists.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(userRepoProvider).watch(user.uid);
});

final sitesProvider = StreamProvider<List<Site>>(
  (ref) => ref.watch(siteRepoProvider).watchAll(),
);

final shiftsProvider = StreamProvider<List<Shift>>(
  (ref) => ref.watch(shiftRepoProvider).watchAll(),
);

final employeesProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userRepoProvider).watchAll(),
);

/// All records with date keys in the inclusive range (admin).
final attendanceRangeProvider =
    StreamProvider.family<List<AttendanceRecord>, (String, String)>(
      (ref, range) =>
          ref.watch(attendanceRepoProvider).watchRange(range.$1, range.$2),
    );

final pendingReviewProvider = StreamProvider<List<AttendanceRecord>>(
  (ref) => ref.watch(attendanceRepoProvider).watchPendingReview(),
);
