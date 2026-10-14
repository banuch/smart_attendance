import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_config.dart';
import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/theme.dart';
import '../../core/utils/dates.dart';
import 'common.dart';

/// Full detail of one attendance record with photos, map and review actions.
class AttendanceDetailDialog extends ConsumerStatefulWidget {
  const AttendanceDetailDialog({super.key, required this.record});

  final AttendanceRecord record;

  static Future<void> show(BuildContext context, AttendanceRecord record) =>
      showDialog(
        context: context,
        builder: (_) => AttendanceDetailDialog(record: record),
      );

  @override
  ConsumerState<AttendanceDetailDialog> createState() =>
      _AttendanceDetailDialogState();
}

class _AttendanceDetailDialogState
    extends ConsumerState<AttendanceDetailDialog> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _review(ReviewDecision decision) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(attendanceRepoProvider)
          .review(
            widget.record.id,
            decision: decision,
            reviewerUid: ref.read(authProvider).currentUser!.uid,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save review: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final employees = ref.watch(employeesProvider).value ?? const <AppUser>[];
    final employee = employees.where((e) => e.uid == r.uid).firstOrNull;
    final sites = ref.watch(sitesProvider).value ?? const [];
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
        child: Column(
          children: [
            ListTile(
              title: Text(r.employeeName, style: theme.textTheme.titleLarge),
              subtitle: Text(dayFormat.format(parseDateKey(r.date))),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _FaceColumn('Registered face', employee?.faceUrl, null),
                      _FaceColumn('Check in', r.checkIn.photoUrl, r.checkIn),
                      if (r.checkOut != null)
                        _FaceColumn('Check out', r.checkOut!.photoUrl, r.checkOut),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 260,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SiteMap(
                        sites: sites,
                        center: LatLng(r.checkIn.lat, r.checkIn.lng),
                        zoom: 16,
                        pins: [
                          MapPin(
                            LatLng(r.checkIn.lat, r.checkIn.lng),
                            'Check in',
                            color: Colors.green,
                          ),
                          if (r.checkOut != null)
                            MapPin(
                              LatLng(r.checkOut!.lat, r.checkOut!.lng),
                              'Check out',
                              color: Colors.red,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (r.reviewed) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Reviewed: ${r.reviewDecision?.name ?? '-'}'
                      '${r.reviewNote == null ? '' : ' — ${r.reviewNote}'}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ],
              ),
            ),
            if (r.flagged) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _note,
                        decoration: const InputDecoration(
                          labelText: 'Review note (optional)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _review(ReviewDecision.rejected),
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text('Reject'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _review(ReviewDecision.approved),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FaceColumn extends StatelessWidget {
  const _FaceColumn(this.title, this.url, this.punch);

  final String title;
  final String? url;
  final Punch? punch;

  @override
  Widget build(BuildContext context) {
    final p = punch;
    final small = Theme.of(context).textTheme.bodySmall;
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SelfieThumb(url, size: 220),
          if (p != null) ...[
            const SizedBox(height: 6),
            Text(timeFormat.format(p.time), style: Theme.of(context).textTheme.titleMedium),
            Text('${p.siteName} · ${p.distanceMeters.round()} m from centre', style: small),
            Text('GPS ±${p.accuracy.round()} m', style: small),
            Text(
              p.faceScore == null
                  ? 'Face: not verified'
                  : 'Face match: ${(p.faceScore! * 100).round()}%',
              style: small,
            ),
            for (final reason in p.flagReasons)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.flag, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      FlagReason.label(reason),
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
