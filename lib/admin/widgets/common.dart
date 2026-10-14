import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/site.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: theme.textTheme.headlineSmall),
                  Text(label, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selfie thumbnail; tap to view full size.
class SelfieThumb extends StatelessWidget {
  const SelfieThumb(this.url, {super.key, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.no_photography_outlined, color: Colors.grey),
      );
    }
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          child: InkWell(
            onTap: () => Navigator.pop(c),
            child: Image.network(u, fit: BoxFit.contain),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          u,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => SizedBox(
            width: size,
            height: size,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

class MapPin {
  const MapPin(this.point, this.label, {this.color = Colors.blue});

  final LatLng point;
  final String label;
  final Color color;
}

/// OpenStreetMap view with site geofences and optional pins.
class SiteMap extends StatelessWidget {
  const SiteMap({
    super.key,
    required this.sites,
    this.pins = const [],
    this.center,
    this.zoom = 15,
    this.onTap,
    this.controller,
  });

  final List<Site> sites;
  final List<MapPin> pins;
  final LatLng? center;
  final double zoom;
  final void Function(LatLng point)? onTap;
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final fallback = sites.isNotEmpty
        ? LatLng(sites.first.lat, sites.first.lng)
        : pins.isNotEmpty
        ? pins.first.point
        : const LatLng(20.5937, 78.9629);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center ?? fallback,
        initialZoom: sites.isEmpty && pins.isEmpty && center == null ? 4 : zoom,
        onTap: onTap == null ? null : (_, p) => onTap!(p),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.smartattendance.smart_attendance',
        ),
        CircleLayer(
          circles: [
            for (final s in sites)
              CircleMarker(
                point: LatLng(s.lat, s.lng),
                radius: s.radiusMeters,
                useRadiusInMeter: true,
                color: Colors.blue.withValues(alpha: 0.15),
                borderColor: Colors.blue,
                borderStrokeWidth: 2,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final s in sites)
              Marker(
                point: LatLng(s.lat, s.lng),
                width: 36,
                height: 36,
                child: Tooltip(
                  message: s.name,
                  child: const Icon(Icons.business, color: Colors.blue),
                ),
              ),
            for (final p in pins)
              Marker(
                point: p.point,
                width: 36,
                height: 36,
                alignment: Alignment.topCenter,
                child: Tooltip(
                  message: p.label,
                  child: Icon(Icons.location_on, color: p.color, size: 36),
                ),
              ),
          ],
        ),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.message, {super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Confirm',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
