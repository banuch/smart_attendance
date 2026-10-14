import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/shift.dart';
import '../models/site.dart';

class UserRepository {
  UserRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');

  Stream<AppUser?> watch(String uid) => _col
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  Stream<List<AppUser>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  Future<void> create(AppUser user) => _col.doc(user.uid).set({
    ...user.toProfileMap(),
    'deviceId': null,
    'faceEmbedding': null,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> updateProfile(AppUser user) =>
      _col.doc(user.uid).update(user.toProfileMap());

  /// Called by the employee on first login from a device.
  Future<void> bindDevice(String uid, String deviceId, String model) =>
      _col.doc(uid).update({
        'deviceId': deviceId,
        'deviceModel': model,
        'deviceBoundAt': FieldValue.serverTimestamp(),
      });

  Future<void> resetDevice(String uid) => _col.doc(uid).update({
    'deviceId': null,
    'deviceModel': null,
    'deviceBoundAt': null,
  });

  /// Called by the employee once, during face enrollment.
  Future<void> enrollFace(
    String uid, {
    required List<double> embedding,
    required String url,
    required String path,
  }) => _col.doc(uid).update({
    'faceEmbedding': embedding,
    'faceUrl': url,
    'facePath': path,
    'faceEnrolledAt': FieldValue.serverTimestamp(),
  });

  Future<void> resetFace(String uid) => _col.doc(uid).update({
    'faceEmbedding': null,
    'faceUrl': null,
    'facePath': null,
    'faceEnrolledAt': null,
  });
}

class SiteRepository {
  SiteRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('sites');

  Stream<List<Site>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Site.fromMap(d.id, d.data())).toList());

  Future<void> save(Site site) => site.id.isEmpty
      ? _col.add(site.toMap())
      : _col.doc(site.id).set(site.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}

class ShiftRepository {
  ShiftRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('shifts');

  Stream<List<Shift>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Shift.fromMap(d.id, d.data())).toList());

  Future<void> save(Shift shift) => shift.id.isEmpty
      ? _col.add(shift.toMap())
      : _col.doc(shift.id).set(shift.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}

class AttendanceRepository {
  AttendanceRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('attendance');

  List<AttendanceRecord> _records(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map(AttendanceRecord.fromDoc).toList();

  Stream<AttendanceRecord?> watchDay(String uid, String date) => _col
      .doc(AttendanceRecord.docId(uid, date))
      .snapshots()
      .map((d) => d.exists ? AttendanceRecord.fromDoc(d) : null);

  /// One employee's records in [from, to] (date keys, inclusive).
  Stream<List<AttendanceRecord>> watchUserRange(
    String uid,
    String from,
    String to,
  ) => _col
      .where('uid', isEqualTo: uid)
      .where('date', isGreaterThanOrEqualTo: from)
      .where('date', isLessThanOrEqualTo: to)
      .orderBy('date', descending: true)
      .snapshots()
      .map(_records);

  /// All employees' records in [from, to] (admin only).
  Stream<List<AttendanceRecord>> watchRange(String from, String to) => _col
      .where('date', isGreaterThanOrEqualTo: from)
      .where('date', isLessThanOrEqualTo: to)
      .orderBy('date', descending: true)
      .snapshots()
      .map(_records);

  Stream<List<AttendanceRecord>> watchPendingReview() => _col
      .where('flagged', isEqualTo: true)
      .where('reviewed', isEqualTo: false)
      .snapshots()
      .map(_records);

  Future<void> checkIn({
    required String uid,
    required String employeeName,
    required String date,
    required String? shiftId,
    required Punch punch,
  }) => _col.doc(AttendanceRecord.docId(uid, date)).set({
    'uid': uid,
    'employeeName': employeeName,
    'date': date,
    'shiftId': shiftId,
    'checkIn': punch.toWriteMap(),
    'flagged': punch.flagged,
    'reviewed': false,
  });

  Future<void> checkOut(AttendanceRecord record, Punch punch) =>
      _col.doc(record.id).update({
        'checkOut': punch.toWriteMap(),
        'flagged': record.flagged || punch.flagged,
        'reviewed': record.reviewed && !punch.flagged,
      });

  Future<void> review(
    String id, {
    required ReviewDecision decision,
    required String reviewerUid,
    String? note,
  }) => _col.doc(id).update({
    'reviewed': true,
    'reviewDecision': decision.name,
    'reviewedBy': reviewerUid,
    'reviewedAt': FieldValue.serverTimestamp(),
    'reviewNote': note,
  });
}
