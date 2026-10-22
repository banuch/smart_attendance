const EARTH_RADIUS_METERS = 6371000;
const rad = (deg) => (deg * Math.PI) / 180;

/** Great-circle distance between two coordinates, in metres (haversine). */
export function distanceMeters(lat1, lng1, lat2, lng2) {
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(a));
}

/**
 * The site closest to the point, or null when [sites] is empty. Sites the
 * point is inside of win over nearer sites it is outside of.
 */
export function nearestSite(lat, lng, sites) {
  let best = null;
  for (const site of sites) {
    const distance = distanceMeters(lat, lng, site.lat, site.lng);
    const m = { site, distance, inside: distance <= site.radiusMeters };
    if (
      best === null ||
      (m.inside && !best.inside) ||
      (m.inside === best.inside && m.distance < best.distance)
    ) {
      best = m;
    }
  }
  return best;
}
