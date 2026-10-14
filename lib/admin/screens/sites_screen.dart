import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/data/providers.dart';
import '../../core/models/site.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

class SitesScreen extends ConsumerWidget {
  const SitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sitesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => SiteFormDialog.show(context),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add site'),
      ),
      body: sites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(Icons.error_outline, 'Could not load: $e'),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(height: 320, child: SiteMap(sites: list)),
            ),
            const SizedBox(height: 16),
            if (list.isEmpty)
              const EmptyState(
                Icons.location_off_outlined,
                'No sites yet. Add your office so employees can check in there.',
              ),
            for (final s in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.business),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.address.isEmpty ? '' : '${s.address}\n'}'
                    '${s.lat.toStringAsFixed(6)}, ${s.lng.toStringAsFixed(6)} · '
                    'radius ${s.radiusMeters.round()} m',
                  ),
                  isThreeLine: s.address.isNotEmpty,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => SiteFormDialog.show(context, site: s),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(
                            context,
                            'Delete ${s.name}?',
                            'Employees assigned only to this site will not be '
                                'able to check in until reassigned.',
                            action: 'Delete',
                          )) {
                            await ref.read(siteRepoProvider).delete(s.id);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SiteFormDialog extends ConsumerStatefulWidget {
  const SiteFormDialog({super.key, this.site});

  final Site? site;

  static Future<void> show(BuildContext context, {Site? site}) => showDialog(
    context: context,
    builder: (_) => SiteFormDialog(site: site),
  );

  @override
  ConsumerState<SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends ConsumerState<SiteFormDialog> {
  final _form = GlobalKey<FormState>();
  final _map = MapController();
  late final _name = TextEditingController(text: widget.site?.name);
  late final _address = TextEditingController(text: widget.site?.address);
  late final _lat = TextEditingController(text: widget.site?.lat.toString());
  late final _lng = TextEditingController(text: widget.site?.lng.toString());
  late double _radius = widget.site?.radiusMeters ?? 100;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  LatLng? get _point {
    final lat = double.tryParse(_lat.text);
    final lng = double.tryParse(_lng.text);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  void _setPoint(LatLng p) => setState(() {
    _lat.text = p.latitude.toStringAsFixed(6);
    _lng.text = p.longitude.toStringAsFixed(6);
  });

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(siteRepoProvider).save(
        Site(
          id: widget.site?.id ?? '',
          name: _name.text.trim(),
          address: _address.text.trim(),
          lat: double.parse(_lat.text),
          lng: double.parse(_lng.text),
          radiusMeters: _radius,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _coordValidator(String? v, double limit) {
    final d = double.tryParse(v ?? '');
    if (d == null || d.abs() > limit) return 'Invalid';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    final preview = point == null
        ? <Site>[]
        : [
            Site(
              id: '',
              name: _name.text,
              lat: point.latitude,
              lng: point.longitude,
              radiusMeters: _radius,
            ),
          ];
    return AlertDialog(
      title: Text(widget.site == null ? 'Add site' : 'Edit site'),
      content: SizedBox(
        width: 640,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Site name *'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lat,
                        decoration: const InputDecoration(labelText: 'Latitude *'),
                        validator: (v) => _coordValidator(v, 90),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lng,
                        decoration: const InputDecoration(labelText: 'Longitude *'),
                        validator: (v) => _coordValidator(v, 180),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Centre map on coordinates',
                      icon: const Icon(Icons.my_location),
                      onPressed: point == null ? null : () => _map.move(point, 17),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tip: click on the map to set the location, or paste '
                  'coordinates from Google Maps.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 300,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SiteMap(
                      controller: _map,
                      sites: preview,
                      center: point,
                      zoom: point == null ? 4 : 17,
                      onTap: _setPoint,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Radius'),
                    Expanded(
                      child: Slider(
                        min: 25,
                        max: 1000,
                        divisions: 39,
                        value: _radius,
                        label: '${_radius.round()} m',
                        onChanged: (v) => setState(() => _radius = v),
                      ),
                    ),
                    SizedBox(width: 64, child: Text('${_radius.round()} m')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
