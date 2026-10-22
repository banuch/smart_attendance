import 'dart:convert';
import 'dart:typed_data';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/shift.dart';
import '../models/site.dart';
import 'api_client.dart';

List<T> _list<T>(dynamic json, T Function(Map<String, dynamic>) parse) => [
  for (final m in json as List) parse(Map<String, dynamic>.from(m as Map)),
];

Map<String, dynamic> _map(dynamic json) =>
    Map<String, dynamic>.from(json as Map);

class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  Future<AppUser> me() async =>
      AppUser.fromJson(_map(await _api.get('/api/me')));

  Stream<AppUser?> watchMe() => poll(_api, me);

  Stream<List<AppUser>> watchAll() => poll(
    _api,
    () async => _list(await _api.get('/api/users'), AppUser.fromJson),
    every: const Duration(seconds: 60),
  );

  /// Creates the login and profile. Admin only.
  Future<void> create(AppUser user, String password) =>
      _api.post('/api/users', {...user.toProfileMap(), 'password': password});

  Future<void> updateProfile(AppUser user) =>
      _api.put('/api/users/${user.uid}', user.toProfileMap());

  /// Called by the employee on first login from a device.
  Future<void> bindDevice(String deviceId, String model) =>
      _api.post('/api/me/device', {'deviceId': deviceId, 'deviceModel': model});

  Future<void> resetDevice(String uid) =>
      _api.post('/api/users/$uid/reset-device');

  /// Called by the employee once, during face enrollment.
  Future<void> enrollFace({
    required List<double> embedding,
    required Uint8List jpeg,
  }) => _api.postPhoto(
    '/api/me/face',
    jpeg: jpeg,
    fields: {'embedding': jsonEncode(embedding)},
  );

  Future<void> resetFace(String uid) => _api.post('/api/users/$uid/reset-face');

  /// Sets a new password; the user is signed out on every device.
  Future<void> setPassword(String uid, String password) =>
      _api.post('/api/users/$uid/password', {'password': password});
}

class SiteRepository {
  SiteRepository(this._api);

  final ApiClient _api;

  Stream<List<Site>> watchAll() => poll(
    _api,
    () async => _list(await _api.get('/api/sites'), Site.fromJson),
    every: const Duration(seconds: 60),
  );

  Future<void> save(Site site) => site.id.isEmpty
      ? _api.post('/api/sites', site.toMap())
      : _api.put('/api/sites/${site.id}', site.toMap());

  Future<void> delete(String id) => _api.delete('/api/sites/$id');
}

class ShiftRepository {
  ShiftRepository(this._api);

  final ApiClient _api;

  Stream<List<Shift>> watchAll() => poll(
    _api,
    () async => _list(await _api.get('/api/shifts'), Shift.fromJson),
    every: const Duration(seconds: 60),
  );

  Future<void> save(Shift shift) => shift.id.isEmpty
      ? _api.post('/api/shifts', shift.toMap())
      : _api.put('/api/shifts/${shift.id}', shift.toMap());

  Future<void> delete(String id) => _api.delete('/api/shifts/$id');
}

class AttendanceRepository {
  AttendanceRepository(this._api);

  final ApiClient _api;

  Future<List<AttendanceRecord>> _range(Map<String, String> query) async =>
      _list(
        await _api.get('/api/attendance', query: query),
        AttendanceRecord.fromJson,
      );

  /// The signed-in user's record for today (the server decides the day).
  Stream<AttendanceRecord?> watchToday() => poll(_api, () async {
    final res = _map(await _api.get('/api/attendance/today'));
    final record = res['record'];
    return record == null ? null : AttendanceRecord.fromJson(_map(record));
  });

  /// One employee's records in [from, to] (date keys, inclusive). Employees
  /// always get their own records, whatever [uid] says.
  Stream<List<AttendanceRecord>> watchUserRange(
    String uid,
    String from,
    String to,
  ) => poll(_api, () => _range({'from': from, 'to': to, 'uid': uid}));

  /// All employees' records in [from, to] (admin only).
  Stream<List<AttendanceRecord>> watchRange(String from, String to) =>
      poll(_api, () => _range({'from': from, 'to': to}));

  Stream<List<AttendanceRecord>> watchPendingReview() => poll(
    _api,
    () async => _list(
      await _api.get('/api/attendance/pending'),
      AttendanceRecord.fromJson,
    ),
  );

  /// Check-in or check-out; the server decides which, and verifies it.
  Future<AttendanceRecord> punch({
    required double lat,
    required double lng,
    required double accuracy,
    required bool mocked,
    required String deviceId,
    required List<double>? embedding,
    required Uint8List jpeg,
  }) async {
    final res = _map(
      await _api.postPhoto(
        '/api/attendance/punch',
        jpeg: jpeg,
        fields: {
          'lat': '$lat',
          'lng': '$lng',
          'accuracy': '$accuracy',
          'mocked': '$mocked',
          'deviceId': deviceId,
          if (embedding != null) 'embedding': jsonEncode(embedding),
        },
      ),
    );
    return AttendanceRecord.fromJson(_map(res['record']));
  }

  Future<void> review(
    String id, {
    required ReviewDecision decision,
    String? note,
  }) => _api.post('/api/attendance/$id/review', {
    'decision': decision.name,
    'note': note,
  });
}
