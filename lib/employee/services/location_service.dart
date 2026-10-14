import 'package:geolocator/geolocator.dart';

import '../../core/app_config.dart';

class LocationException implements Exception {
  const LocationException(this.message, {this.openSettings = false});

  final String message;
  final bool openSettings;

  @override
  String toString() => message;
}

class LocationService {
  /// Returns a fresh high-accuracy fix, or throws [LocationException].
  /// Mock (fake GPS) locations are rejected.
  Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'Location is turned off. Please enable GPS.',
        openSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission is required.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is permanently denied. Enable it in app settings.',
        openSettings: true,
      );
    }

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: AppConfig.gpsTimeout,
          forceLocationManager: false,
        ),
      );
    } catch (_) {
      throw const LocationException(
        'Could not get your location. Move to an open area and try again.',
      );
    }

    if (position.isMocked) {
      throw const LocationException(
        'Fake GPS detected. Disable mock location apps and try again.',
      );
    }
    return position;
  }

  Future<void> openSettings() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
