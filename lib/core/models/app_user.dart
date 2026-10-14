import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, employee }

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.phone = '',
    this.employeeCode = '',
    this.role = UserRole.employee,
    this.active = true,
    this.siteIds = const [],
    this.shiftId,
    this.deviceId,
    this.deviceModel,
    this.faceEmbedding,
    this.faceUrl,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final String employeeCode;
  final UserRole role;
  final bool active;

  /// Sites the employee may punch at. Empty means any site.
  final List<String> siteIds;
  final String? shiftId;

  /// Device the account is bound to; null until first login.
  final String? deviceId;
  final String? deviceModel;

  /// Reference face embedding; null until the employee enrolls their face.
  final List<double>? faceEmbedding;
  final String? faceUrl;

  bool get isAdmin => role == UserRole.admin;
  bool get faceEnrolled => faceEmbedding != null && faceEmbedding!.isNotEmpty;

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
    uid: uid,
    name: m['name'] as String? ?? '',
    email: m['email'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    employeeCode: m['employeeCode'] as String? ?? '',
    role: m['role'] == 'admin' ? UserRole.admin : UserRole.employee,
    active: m['active'] as bool? ?? true,
    siteIds: (m['siteIds'] as List?)?.cast<String>() ?? const [],
    shiftId: m['shiftId'] as String?,
    deviceId: m['deviceId'] as String?,
    deviceModel: m['deviceModel'] as String?,
    faceEmbedding: (m['faceEmbedding'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList(),
    faceUrl: m['faceUrl'] as String?,
  );

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AppUser.fromMap(doc.id, doc.data() ?? const {});

  /// Fields the admin panel edits. Device / face fields are managed separately.
  Map<String, dynamic> toProfileMap() => {
    'name': name,
    'email': email,
    'phone': phone,
    'employeeCode': employeeCode,
    'role': role.name,
    'active': active,
    'siteIds': siteIds,
    'shiftId': shiftId,
  };
}
