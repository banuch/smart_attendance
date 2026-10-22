import 'package:geolocator/geolocator.dart';

import '../../core/data/api_client.dart';
import '../../core/data/repositories.dart';
import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/models/site.dart';
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

/// Pre-checks the geofence on the phone for quick feedback, then sends the
/// punch to the server, which re-checks everything and matches the face.
class PunchService {
  PunchService({required this.attendance, required this.users});

  final AttendanceRepository attendance;
  final UserRepository users;

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

  Future<void> enrollFace(AppUser user, FaceCapture capture) async {
    if (capture.embedding == null) {
      throw const PunchException(
        'Face recognition model is missing from this build. Contact your admin.',
      );
    }
    try {
      await users.enrollFace(embedding: capture.embedding!, jpeg: capture.jpeg);
    } on ApiException catch (e) {
      throw PunchException(e.message);
    }
  }

  /// Records a check-in (when [today] is null) or check-out, and returns it.
  /// The server's verdict (time, site, face score, flags) is what is shown.
  Future<Punch> submit({
    required AttendanceRecord? today,
    required LocationCheck location,
    required FaceCapture capture,
    required String deviceId,
  }) async {
    final AttendanceRecord record;
    try {
      record = await attendance.punch(
        lat: location.position.latitude,
        lng: location.position.longitude,
        accuracy: location.position.accuracy,
        mocked: location.position.isMocked,
        deviceId: deviceId,
        embedding: capture.embedding,
        jpeg: capture.jpeg,
      );
    } on ApiException catch (e) {
      throw PunchException(e.message);
    }
    return today == null ? record.checkIn : record.checkOut ?? record.checkIn;
  }
}
