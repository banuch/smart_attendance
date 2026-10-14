import 'dart:math' as math;

import '../models/site.dart';

const _earthRadiusMeters = 6371000.0;

/// Great-circle distance between two coordinates, in metres (haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.sqrt(a));
}

class SiteMatch {
  const SiteMatch(this.site, this.distance);

  final Site site;
  final double distance;

  bool get inside => distance <= site.radiusMeters;
}

/// The site closest to the given point, or null if [sites] is empty.
/// Sites the point is inside of win over nearer sites it is outside of.
SiteMatch? nearestSite(double lat, double lng, Iterable<Site> sites) {
  SiteMatch? best;
  for (final site in sites) {
    final m = SiteMatch(site, distanceMeters(lat, lng, site.lat, site.lng));
    if (best == null ||
        (m.inside && !best.inside) ||
        (m.inside == best.inside && m.distance < best.distance)) {
      best = m;
    }
  }
  return best;
}
