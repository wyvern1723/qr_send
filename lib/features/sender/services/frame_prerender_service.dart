import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/rendered_transfer_frame.dart';

class FramePrerenderProgress {
  const FramePrerenderProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get fraction => total == 0 ? 0 : completed / total;
}

class FramePrerenderService {
  const FramePrerenderService();

  double _getActualQRCodeSize({
    required String data,
    required double size,
    required bool gapless,
    int errorCorrectionLevel = QrErrorCorrectLevel.L,
  }) {
    final double gap = gapless ? 0 : 0.25;
    final QrValidationResult validationResult = QrValidator.validate(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: errorCorrectionLevel,
    );

    if (validationResult.status != QrValidationStatus.valid) {
      return size;
    }

    final qrCode = validationResult.qrCode!;
    final double gapTotal = (qrCode.moduleCount - 1) * gap;

    double pixelSize = (size - gapTotal) / qrCode.moduleCount;
    pixelSize = (pixelSize * 2).roundToDouble() / 2;

    return (pixelSize * qrCode.moduleCount) + gapTotal;
  }

  Future<List<RenderedTransferFrame>> renderAllFrames({
    required List<String> encodedFrames,
    required double size,
    ValueChanged<FramePrerenderProgress>? onProgress,
  }) async {
    final renderedFrames = <RenderedTransferFrame>[];
    final total = encodedFrames.length;

    for (var index = 0; index < total; index++) {
      final encodedData = encodedFrames[index];
      final painter = QrPainter(
        data: encodedData,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      );

      final actualSize = _getActualQRCodeSize(
        data: encodedData,
        size: size,
        gapless: true,
      );

      final imageData = await painter.toImageData(actualSize);
      if (imageData == null) {
        throw StateError('Failed to render QR frame $index');
      }

      renderedFrames.add(
        RenderedTransferFrame(
          index: index,
          encodedData: encodedData,
          pngBytes: imageData.buffer.asUint8List(),
        ),
      );

      onProgress?.call(
        FramePrerenderProgress(completed: index + 1, total: total),
      );
    }

    return renderedFrames;
  }
}
