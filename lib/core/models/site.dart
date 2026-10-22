class Site {
  const Site({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.address = '',
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;
  final String address;

  factory Site.fromMap(String id, Map<String, dynamic> m) => Site(
    id: id,
    name: m['name'] as String? ?? '',
    lat: (m['lat'] as num?)?.toDouble() ?? 0,
    lng: (m['lng'] as num?)?.toDouble() ?? 0,
    radiusMeters: (m['radiusMeters'] as num?)?.toDouble() ?? 100,
    address: m['address'] as String? ?? '',
  );

  factory Site.fromJson(Map<String, dynamic> m) =>
      Site.fromMap(m['id'] as String, m);

  Map<String, dynamic> toMap() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'radiusMeters': radiusMeters,
    'address': address,
  };
}
