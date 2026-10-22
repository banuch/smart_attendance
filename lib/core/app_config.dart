/// Tunable constants shared by the employee app and the admin panel.
class AppConfig {
  AppConfig._();

  static const appName = 'Smart Attendance';

  /// Path of the MobileFaceNet model bundled under assets/.
  static const faceModelAsset = 'assets/models/mobilefacenet.tflite';

  /// GPS fixes worse than this (metres) are accepted but flagged for review.
  /// Only used for the on-screen warning; the server applies its own
  /// MAX_GPS_ACCURACY_METERS, as it does FACE_MATCH_THRESHOLD.
  static const maxGpsAccuracyMeters = 50.0;

  /// How long to wait for a GPS fix before giving up.
  static const gpsTimeout = Duration(seconds: 25);

  /// Max longest edge of uploaded selfies, in pixels.
  static const selfieMaxSize = 800;
}

/// Reasons attached to a punch that send it to the admin review queue.
class FlagReason {
  FlagReason._();

  static const faceMismatch = 'face_mismatch';
  static const faceNotVerified = 'face_not_verified';
  static const lowGpsAccuracy = 'low_gps_accuracy';

  static String label(String reason) => switch (reason) {
    faceMismatch => 'Face does not match',
    faceNotVerified => 'Face could not be verified',
    lowGpsAccuracy => 'Low GPS accuracy',
    _ => reason,
  };
}
