import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/app_config.dart';
import '../../core/data/repositories.dart';
import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/models/site.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/face_math.dart';
import '../../core/utils/geo.dart';
import 'face_service.dart';

class PunchException implements Exception {
  const PunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Result of the location step, shown to the user before the selfie.
class LocationCheck {
  const LocationCheck(this.position, this.match);

  final Position position;
  final SiteMatch match;
}

/// Orchestrates geofence check, face verification, upload and record write.
class PunchService {
  PunchService({
    required this.attendance,
    required this.users,
    required this.storage,
  });

  final AttendanceRepository attendance;
  final UserRepository users;
  final FirebaseStorage storage;

  /// Sites the employee may punch at (all sites when none are assigned).
  static List<Site> allowedSites(AppUser user, List<Site> sites) =>
      user.siteIds.isEmpty
      ? sites
      : sites.where((s) => user.siteIds.contains(s.id)).toList();

  LocationCheck checkGeofence(
    Position position,
    AppUser user,
    List<Site> sites,
  ) {
    final allowed = allowedSites(user, sites);
    if (allowed.isEmpty) {
      throw const PunchException(
        'No work site is configured for you. Contact your admin.',
      );
    }
    final match = nearestSite(position.latitude, position.longitude, allowed)!;
    if (!match.inside) {
      throw PunchException(
        'You are ${match.distance.round()} m from ${match.site.name}. '
        'Move within ${match.site.radiusMeters.round()} m to punch.',
      );
    }
    return LocationCheck(position, match);
  }

  Future<({String url, String path})> _upload(String path, FaceCapture c) async {
    final ref = storage.ref(path);
    await ref.putData(c.jpeg, SettableMetadata(contentType: 'image/jpeg'));
    return (url: await ref.getDownloadURL(), path: path);
  }

  Future<void> enrollFace(AppUser user, FaceCapture capture) async {
    if (capture.embedding == null) {
      throw const PunchException(
        'Face recognition model is missing from this build. Contact your admin.',
      );
    }
    final file = await _upload(
      'faces/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
      capture,
    );
    await users.enrollFace(
      user.uid,
      embedding: capture.embedding!,
      url: file.url,
      path: file.path,
    );
  }

  /// Records a check-in (when [today] is null) or check-out.
  Future<Punch> submit({
    required AppUser user,
    required AttendanceRecord? today,
    required LocationCheck location,
    required FaceCapture capture,
    required String deviceId,
  }) async {
    final date = today?.date ?? dateKey(DateTime.now());
    final kind = today == null ? 'in' : 'out';

    final reasons = <String>[];
    double? score;
    if (capture.embedding != null && user.faceEnrolled) {
      score = cosineSimilarity(capture.embedding!, user.faceEmbedding!);
      if (score < AppConfig.faceMatchThreshold) {
        reasons.add(FlagReason.faceMismatch);
      }
    } else {
      reasons.add(FlagReason.faceNotVerified);
    }
    if (location.position.accuracy > AppConfig.maxGpsAccuracyMeters) {
      reasons.add(FlagReason.lowGpsAccuracy);
    }

    final file = await _upload(
      'selfies/${user.uid}/${date}_${kind}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      capture,
    );

    final punch = Punch(
      time: DateTime.now(),
      lat: location.position.latitude,
      lng: location.position.longitude,
      accuracy: location.position.accuracy,
      siteId: location.match.site.id,
      siteName: location.match.site.name,
      distanceMeters: location.match.distance,
      photoUrl: file.url,
      photoPath: file.path,
      faceScore: score,
      flagReasons: reasons,
      deviceId: deviceId,
    );

    if (today == null) {
      await attendance.checkIn(
        uid: user.uid,
        employeeName: user.name,
        date: date,
        shiftId: user.shiftId,
        punch: punch,
      );
    } else {
      await attendance.checkOut(today, punch);
    }
    return punch;
  }
}
