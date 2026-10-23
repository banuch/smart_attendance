import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme.dart';
import '../employee_providers.dart';
import '../services/face_service.dart';
import '../services/punch_service.dart';
import 'selfie_capture_screen.dart';

/// One-time capture of the reference face used to verify later selfies.
class EnrollFaceScreen extends ConsumerStatefulWidget {
  const EnrollFaceScreen({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<EnrollFaceScreen> createState() => _EnrollFaceScreenState();
}

class _EnrollFaceScreenState extends ConsumerState<EnrollFaceScreen> {
  FaceCapture? _capture;
  bool _busy = false;

  /// Why the last photo was rejected. Stays on screen until the next try, as
  /// a snackbar is easy to miss.
  String? _error;

  Future<void> _takePhoto() async {
    final path = await SelfieCaptureScreen.open(
      context,
      title: 'Register your face',
    );
    if (path == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final capture = await ref.read(faceServiceProvider).process(path);
      setState(() => _capture = capture);
    } on FaceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Face processing failed: $e\n$st');
      if (mounted) setState(() => _error = 'Could not process the photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(punchServiceProvider).enrollFace(widget.user, _capture!);
      // The gate rebuilds to the home screen once the profile updates.
    } on PunchException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Uint8List? photo = _capture?.jpeg;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register your face'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authStateProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Hi ${widget.user.name},', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Before your first check-in, take a clear selfie. It is used to '
              'confirm that it is you each time you mark attendance.',
            ),
            const SizedBox(height: 16),
            const _Tip(Icons.wb_sunny_outlined, 'Face a light source'),
            const _Tip(
              Icons.face_retouching_off,
              'Remove sunglasses, mask or cap',
            ),
            const _Tip(Icons.person_outline, 'Only you in the frame'),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
            ],
            if (photo != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(photo, height: 280, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 24),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (photo == null)
              FilledButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_front),
                label: const Text('Take selfie'),
              )
            else ...[
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Use this photo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _takePhoto,
                child: const Text('Retake'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(text),
      ],
    ),
  );
}
