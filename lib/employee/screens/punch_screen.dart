import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/data/providers.dart';
import '../../core/models/attendance_record.dart';
import '../../core/utils/dates.dart';
import '../employee_providers.dart';
import '../services/face_service.dart';
import '../services/location_service.dart';
import '../services/punch_service.dart';
import 'selfie_capture_screen.dart';

enum _Step { locating, located, processing, uploading, done, failed }

/// Check-in / check-out flow: GPS + geofence → live selfie → face check →
/// upload → record.
class PunchScreen extends ConsumerStatefulWidget {
  const PunchScreen({super.key, required this.today});

  /// Today's record when checking out; null when checking in.
  final AttendanceRecord? today;

  @override
  ConsumerState<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends ConsumerState<PunchScreen> {
  _Step _step = _Step.locating;
  String? _error;
  bool _canOpenSettings = false;
  LocationCheck? _location;
  Punch? _result;

  bool get _isCheckIn => widget.today == null;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  void _fail(String message, {bool settings = false}) {
    if (!mounted) return;
    setState(() {
      _step = _Step.failed;
      _error = message;
      _canOpenSettings = settings;
    });
  }

  Future<void> _locate() async {
    setState(() {
      _step = _Step.locating;
      _error = null;
    });
    try {
      final position = await ref.read(locationServiceProvider).currentPosition();
      final user = ref.read(currentUserProvider).value!;
      final sites = await ref.read(sitesProvider.future);
      final check = ref
          .read(punchServiceProvider)
          .checkGeofence(position, user, sites);
      if (!mounted) return;
      setState(() {
        _location = check;
        _step = _Step.located;
      });
    } on LocationException catch (e) {
      _fail(e.message, settings: e.openSettings);
    } on PunchException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Location check failed: $e');
    }
  }

  Future<void> _selfieAndSubmit() async {
    final path = await SelfieCaptureScreen.open(
      context,
      title: _isCheckIn ? 'Check-in selfie' : 'Check-out selfie',
    );
    if (path == null || !mounted) return;

    setState(() => _step = _Step.processing);
    try {
      final capture = await ref.read(faceServiceProvider).process(path);
      if (!mounted) return;
      setState(() => _step = _Step.uploading);
      final device = await ref.read(deviceIdentityProvider.future);
      final punch = await ref
          .read(punchServiceProvider)
          .submit(
            user: ref.read(currentUserProvider).value!,
            today: widget.today,
            location: _location!,
            capture: capture,
            deviceId: device.id,
          );
      if (!mounted) return;
      setState(() {
        _result = punch;
        _step = _Step.done;
      });
    } on FaceException catch (e) {
      // Keep the location fix; let the user retake the selfie.
      if (!mounted) return;
      setState(() {
        _step = _Step.located;
        _error = e.message;
      });
    } on PunchException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Could not save attendance. Check your internet and retry.\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _Step.processing && _step != _Step.uploading,
      child: Scaffold(
        appBar: AppBar(title: Text(_isCheckIn ? 'Check in' : 'Check out')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (_step) {
      case _Step.locating:
        return const _Progress('Getting your location…');
      case _Step.processing:
        return const _Progress('Verifying your face…');
      case _Step.uploading:
        return const _Progress('Saving attendance…');
      case _Step.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 72, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error ?? 'Something went wrong', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_canOpenSettings)
              OutlinedButton(
                onPressed: () => ref.read(locationServiceProvider).openSettings(),
                child: const Text('Open settings'),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _locate, child: const Text('Try again')),
          ],
        );
      case _Step.located:
        final loc = _location!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.where_to_vote, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text('You are at ${loc.match.site.name}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${loc.match.distance.round()} m from site centre · '
              'GPS ±${loc.position.accuracy.round()} m',
            ),
            if (loc.position.accuracy > AppConfig.maxGpsAccuracyMeters)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'GPS signal is weak; this punch will be reviewed.',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _selfieAndSubmit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              icon: const Icon(Icons.camera_front),
              label: Text(_error == null ? 'Take selfie' : 'Retake selfie'),
            ),
          ],
        );
      case _Step.done:
        final p = _result!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 96, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              _isCheckIn ? 'Checked in' : 'Checked out',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text('${timeFormat.format(p.time)} at ${p.siteName}'),
            if (p.flagged) ...[
              const SizedBox(height: 16),
              Text(
                'Recorded, but sent to your admin for review:\n'
                '${p.flagReasons.map(FlagReason.label).join(', ')}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
    }
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text(label),
    ],
  );
}
