import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/app_config.dart';
import '../../core/utils/face_math.dart';

class FaceException implements Exception {
  const FaceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A processed selfie: compressed JPEG for upload plus the face embedding.
class FaceCapture {
  const FaceCapture({required this.jpeg, this.embedding});

  final Uint8List jpeg;

  /// L2-normalised embedding; null when the recognition model is unavailable.
  final List<double>? embedding;
}

/// Face detection (ML Kit) and recognition (MobileFaceNet via TFLite).
class FaceService {
  FaceService();

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.2,
    ),
  );

  Interpreter? _interpreter;
  bool _modelLoadAttempted = false;

  bool get recognitionAvailable => _interpreter != null;

  Future<void> _loadModel() async {
    if (_modelLoadAttempted) return;
    _modelLoadAttempted = true;
    try {
      _interpreter = await Interpreter.fromAsset(AppConfig.faceModelAsset);
    } catch (e) {
      debugPrint('Face model not loaded (${AppConfig.faceModelAsset}): $e');
    }
  }

  /// Validates that the photo at [path] contains exactly one face, then
  /// returns the compressed image and the face embedding.
  Future<FaceCapture> process(String path) async {
    await _loadModel();

    // Normalise orientation & size first so ML Kit and the cropper agree on
    // coordinates.
    final jpeg = await Isolate.run(() => _normalise(path));
    final dir = await getTemporaryDirectory();
    final normalised = File(
      '${dir.path}/face_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await normalised.writeAsBytes(jpeg);

    try {
      final faces = await _detector.processImage(
        InputImage.fromFilePath(normalised.path),
      );
      if (faces.isEmpty) {
        throw const FaceException(
          'No face found. Hold the phone at eye level in good light.',
        );
      }
      if (faces.length > 1) {
        throw const FaceException(
          'More than one face found. Only you should be in the photo.',
        );
      }

      final interpreter = _interpreter;
      if (interpreter == null) return FaceCapture(jpeg: jpeg);

      final box = faces.single.boundingBox;
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      final size = inputShape[1];
      final input = await Isolate.run(
        () => _faceTensor(jpeg, box.left, box.top, box.width, box.height, size),
      );
      final output = [List<double>.filled(outputShape.last, 0)];
      interpreter.run([input], output);
      return FaceCapture(jpeg: jpeg, embedding: l2Normalize(output.first));
    } finally {
      normalised.delete().ignore();
    }
  }

  void dispose() {
    _detector.close();
    _interpreter?.close();
  }
}

Uint8List _normalise(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FaceException('Could not read the photo.');
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > AppConfig.selfieMaxSize) {
    image = image.width >= image.height
        ? img.copyResize(image, width: AppConfig.selfieMaxSize)
        : img.copyResize(image, height: AppConfig.selfieMaxSize);
  }
  return img.encodeJpg(image, quality: 85);
}

/// Crops the face (with a small margin), resizes to [size]×[size] and returns
/// pixels as [size][size][3] floats normalised to [-1, 1].
List<List<List<double>>> _faceTensor(
  Uint8List jpeg,
  double left,
  double top,
  double width,
  double height,
  int size,
) {
  final image = img.decodeJpg(jpeg)!;
  final margin = 0.1;
  final x = (left - width * margin).clamp(0, image.width - 1).toInt();
  final y = (top - height * margin).clamp(0, image.height - 1).toInt();
  final w = (width * (1 + 2 * margin)).clamp(1, image.width - x).toInt();
  final h = (height * (1 + 2 * margin)).clamp(1, image.height - y).toInt();
  final face = img.copyResize(
    img.copyCrop(image, x: x, y: y, width: w, height: h),
    width: size,
    height: size,
  );
  return List.generate(
    size,
    (row) => List.generate(size, (col) {
      final p = face.getPixel(col, row);
      return [
        (p.r - 127.5) / 128.0,
        (p.g - 127.5) / 128.0,
        (p.b - 127.5) / 128.0,
      ];
    }),
  );
}
