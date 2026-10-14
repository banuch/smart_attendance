import 'package:cloud_firestore/cloud_firestore.dart';

/// One check-in or check-out event.
class Punch {
  const Punch({
    required this.time,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.siteId,
    required this.siteName,
    required this.distanceMeters,
    required this.photoUrl,
    required this.photoPath,
    this.faceScore,
    this.flagReasons = const [],
    this.deviceId = '',
  });

  final DateTime time;
  final double lat;
  final double lng;
  final double accuracy;
  final String siteId;
  final String siteName;
  final double distanceMeters;
  final String photoUrl;
  final String photoPath;

  /// Cosine similarity to the enrolled face; null when not verified.
  final double? faceScore;
  final List<String> flagReasons;
  final String deviceId;

  bool get flagged => flagReasons.isNotEmpty;

  factory Punch.fromMap(Map<String, dynamic> m) => Punch(
    // A pending server timestamp reads as null in the local snapshot.
    time: (m['time'] as Timestamp?)?.toDate() ?? DateTime.now(),
    lat: (m['lat'] as num?)?.toDouble() ?? 0,
    lng: (m['lng'] as num?)?.toDouble() ?? 0,
    accuracy: (m['accuracy'] as num?)?.toDouble() ?? 0,
    siteId: m['siteId'] as String? ?? '',
    siteName: m['siteName'] as String? ?? '',
    distanceMeters: (m['distanceMeters'] as num?)?.toDouble() ?? 0,
    photoUrl: m['photoUrl'] as String? ?? '',
    photoPath: m['photoPath'] as String? ?? '',
    faceScore: (m['faceScore'] as num?)?.toDouble(),
    flagReasons: (m['flagReasons'] as List?)?.cast<String>() ?? const [],
    deviceId: m['deviceId'] as String? ?? '',
  );

  /// Map written to Firestore; `time` is always the server's clock.
  Map<String, dynamic> toWriteMap() => {
    'time': FieldValue.serverTimestamp(),
    'lat': lat,
    'lng': lng,
    'accuracy': accuracy,
    'siteId': siteId,
    'siteName': siteName,
    'distanceMeters': distanceMeters,
    'photoUrl': photoUrl,
    'photoPath': photoPath,
    'faceScore': faceScore,
    'flagReasons': flagReasons,
    'deviceId': deviceId,
  };
}

enum ReviewDecision { approved, rejected }

/// One employee's attendance for one calendar day.
/// Document id: `{uid}_{yyyy-MM-dd}`.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.date,
    required this.checkIn,
    this.checkOut,
    this.shiftId,
    this.flagged = false,
    this.reviewed = false,
    this.reviewDecision,
    this.reviewNote,
  });

  final String id;
  final String uid;
  final String employeeName;
  final String date;
  final String? shiftId;
  final Punch checkIn;
  final Punch? checkOut;
  final bool flagged;
  final bool reviewed;
  final ReviewDecision? reviewDecision;
  final String? reviewNote;

  static String docId(String uid, String date) => '${uid}_$date';

  bool get pendingReview => flagged && !reviewed;
  bool get rejected => reviewDecision == ReviewDecision.rejected;

  factory AttendanceRecord.fromMap(String id, Map<String, dynamic> m) =>
      AttendanceRecord(
        id: id,
        uid: m['uid'] as String? ?? '',
        employeeName: m['employeeName'] as String? ?? '',
        date: m['date'] as String? ?? '',
        shiftId: m['shiftId'] as String?,
        checkIn: Punch.fromMap(
          Map<String, dynamic>.from(m['checkIn'] as Map? ?? const {}),
        ),
        checkOut: m['checkOut'] == null
            ? null
            : Punch.fromMap(Map<String, dynamic>.from(m['checkOut'] as Map)),
        flagged: m['flagged'] as bool? ?? false,
        reviewed: m['reviewed'] as bool? ?? false,
        reviewDecision: switch (m['reviewDecision']) {
          'approved' => ReviewDecision.approved,
          'rejected' => ReviewDecision.rejected,
          _ => null,
        },
        reviewNote: m['reviewNote'] as String?,
      );

  factory AttendanceRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) =>
      AttendanceRecord.fromMap(d.id, d.data() ?? const {});
}
