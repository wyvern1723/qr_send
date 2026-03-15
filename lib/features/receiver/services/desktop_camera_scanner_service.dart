import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Global helper that returns available cameras.
Future<List<CameraDescription>> getAvailableCameras() async {
  return availableCameras();
}

/// Desktop camera scanning service.
class DesktopCameraScannerService {
  CameraController? _cameraController;
  Timer? _scanTimer;
  bool _isProcessing = false;
  DateTime? _lastScanAt;
  Duration _scanInterval = const Duration(milliseconds: 20);

  final List<String> _availableCameras = [];
  String? _selectedCameraId;

  /// Available camera labels.
  List<String> get availableCameras => List.unmodifiable(_availableCameras);

  /// Currently selected camera id.
  String? get selectedCameraId => _selectedCameraId;

  /// Whether the scanner is running.
  bool get isRunning =>
      (_cameraController?.value.isStreamingImages ?? false) ||
      (_scanTimer?.isActive ?? false);

  /// Camera controller instance.
  CameraController? get cameraController => _cameraController;

  /// Initializes and returns available cameras.
  Future<List<CameraDescription>> initialize() async {
    final cameras = await getAvailableCameras();

    _availableCameras.clear();
    _availableCameras.addAll(
      cameras.map((c) => '${c.name} (${c.lensDirection})'),
    );

    return cameras;
  }

  /// Starts scanning with the given camera.
  Future<void> startScanning({
    required CameraDescription camera,
    required void Function(String) onDetect,
    required void Function(Object) onError,
    Duration scanInterval = const Duration(milliseconds: 20),
  }) async {
    try {
      await stopScanning();

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!_cameraController!.value.isInitialized) {
        throw StateError('Camera initialization failed');
      }

      _selectedCameraId = camera.name;
      _scanInterval = scanInterval;
      _lastScanAt = null;

      if (_cameraController!.supportsImageStreaming()) {
        // Preferred path: direct frame stream scanning (no temp files).
        await _cameraController!.startImageStream((image) {
          unawaited(_captureAndScanFromStream(image, onDetect));
        });
      } else {
        // Fallback path for platforms/plugins without image stream support.
        _scanTimer = Timer.periodic(scanInterval, (_) {
          unawaited(_captureAndScanFromSnapshot(onDetect));
        });
      }
    } catch (e) {
      onError(e);
    }
  }

  /// Processes a streamed camera frame.
  Future<void> _captureAndScanFromStream(
    CameraImage image,
    void Function(String) onDetect,
  ) async {
    if (_isProcessing) return;

    final now = DateTime.now();
    final lastScanAt = _lastScanAt;
    if (lastScanAt != null && now.difference(lastScanAt) < _scanInterval) {
      return;
    }
    _lastScanAt = now;

    _isProcessing = true;

    try {
      final grayscaleBytes = _extractGrayscaleBytes(image);
      if (grayscaleBytes == null) return;

      final result = await Isolate.run(
        () => _decodeQrIsolate(grayscaleBytes, image.width, image.height),
      );

      if (result != null && result.isNotEmpty) {
        onDetect(result);
      }
    } catch (_) {
      // Ignore individual streamed frame failures.
    } finally {
      _isProcessing = false;
    }
  }

  /// Captures a still frame and scans it.
  Future<void> _captureAndScanFromSnapshot(
    void Function(String) onDetect,
  ) async {
    if (_isProcessing || _cameraController == null) return;

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    _isProcessing = true;
    XFile? capturedImage;

    try {
      capturedImage = await controller.takePicture();
      final bytes = await capturedImage.readAsBytes();

      final result = await Isolate.run(() => _decodeJpegIsolate(bytes));

      if (result != null && result.isNotEmpty) {
        onDetect(result);
      }
    } catch (_) {
      // Ignore individual snapshot failures.
    } finally {
      if (capturedImage != null) {
        try {
          final file = File(capturedImage.path);
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Ignore temporary snapshot cleanup failures.
        }
      }

      _isProcessing = false;
    }
  }

  /// Isolate entry point: Decode JPEG bytes
  static Future<String?> _decodeJpegIsolate(Uint8List bytes) async {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      var result = _tryDecodeImage(image);
      if (result != null) return result;

      final rotated180 = img.copyRotate(image, angle: 180);
      result = _tryDecodeImage(rotated180);
      if (result != null) return result;

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Isolate entry point: Decode from raw grayscale bytes
  static Future<String?> _decodeQrIsolate(
    Uint8List grayscaleBytes,
    int width,
    int height,
  ) async {
    try {
      return _decodeQrFromGrayscale(
        grayscaleBytes: grayscaleBytes,
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }

  /// Core decoding logic (runs in Isolate)
  static String? _tryDecodeImage(img.Image image) {
    final grayscale = img.grayscale(image);
    final grayscaleBytes = grayscale.getBytes(order: img.ChannelOrder.red);
    return _decodeQrFromGrayscale(
      grayscaleBytes: grayscaleBytes,
      width: grayscale.width,
      height: grayscale.height,
    );
  }

  /// Decodes QR code text from grayscale bytes.
  static String? _decodeQrFromGrayscale({
    required Uint8List grayscaleBytes,
    required int width,
    required int height,
  }) {
    try {
      final luminanceSource = RGBLuminanceSource(
        width,
        height,
        _toInt32List(grayscaleBytes),
      );
      final binaryBitmap = BinaryBitmap(HybridBinarizer(luminanceSource));

      final reader = QRCodeReader();
      final hints = DecodeHints()..put(DecodeHintType.tryHarder);
      final result = reader.decode(binaryBitmap, hints: hints);

      if (result.text.isNotEmpty) return result.text;
    } catch (_) {
      // Ignore
    }

    try {
      final invertedBytes = _invertBytes(grayscaleBytes);
      final luminanceSource = RGBLuminanceSource(
        width,
        height,
        _toInt32List(invertedBytes),
      );
      final binaryBitmap = BinaryBitmap(HybridBinarizer(luminanceSource));
      final reader = QRCodeReader();
      final hints = DecodeHints()..put(DecodeHintType.tryHarder);
      final result = reader.decode(binaryBitmap, hints: hints);
      if (result.text.isNotEmpty) return result.text;
    } catch (_) {}

    return null;
  }

  /// Fast grayscale extraction from CameraImage (YUV/BGRA)
  Uint8List? _extractGrayscaleBytes(CameraImage image) {
    if (image.planes.isEmpty) return null;

    final width = image.width;
    final height = image.height;
    final output = Uint8List(width * height);

    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final pixelStride = plane.bytesPerPixel ?? 1;

    if (pixelStride == 1) {
      // Luma plane (YUV/NV21/monochrome).
      for (var y = 0; y < height; y++) {
        final sourceStart = y * rowStride;
        final destStart = y * width;
        if (rowStride == width) {
          output.setRange(destStart, destStart + width, bytes, sourceStart);
        } else {
          for (var x = 0; x < width; x++) {
            output[destStart + x] = bytes[sourceStart + x];
          }
        }
      }
      return output;
    }

    if (pixelStride >= 3 && image.planes.length == 1) {
      // Packed color plane (desktop typically BGRA8888).
      for (var y = 0; y < height; y++) {
        final rowStart = y * rowStride;
        for (var x = 0; x < width; x++) {
          final sourceIndex = rowStart + (x * pixelStride);
          if (sourceIndex + 2 >= bytes.length) return null;
          final c0 = bytes[sourceIndex];
          final c1 = bytes[sourceIndex + 1];
          final c2 = bytes[sourceIndex + 2];
          output[(y * width) + x] = ((c0 + c1 + c2) ~/ 3);
        }
      }
      return output;
    }

    return null;
  }

  /// Stops scanning.
  Future<void> stopScanning() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isProcessing = false;
    _lastScanAt = null;

    final controller = _cameraController;
    _cameraController = null;
    _selectedCameraId = null;

    if (controller == null) return;

    try {
      if (controller.supportsImageStreaming() &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    await controller.dispose();
  }

  /// Switches to the next camera.
  Future<void> switchCamera({
    required List<CameraDescription> cameras,
    required void Function(String) onDetect,
    required void Function(Object) onError,
  }) async {
    if (cameras.length < 2) return;

    final currentIndex = cameras.indexWhere((c) => c.name == _selectedCameraId);
    final nextIndex = (currentIndex + 1) % cameras.length;

    await startScanning(
      camera: cameras[nextIndex],
      onDetect: onDetect,
      onError: onError,
    );
  }

  /// Releases resources.
  void dispose() {
    unawaited(stopScanning());
  }

  // --- Static Helpers for Isolate ---

  static Int32List _toInt32List(Uint8List bytes) {
    final int32List = Int32List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      final value = bytes[i];
      int32List[i] = 0xFF000000 | (value << 16) | (value << 8) | value;
    }
    return int32List;
  }

  static Uint8List _invertBytes(Uint8List bytes) {
    final output = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      output[i] = 255 - bytes[i];
    }
    return output;
  }
}
