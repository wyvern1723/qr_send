import 'dart:typed_data';

import 'package:flutter/painting.dart';

class RenderedTransferFrame {
  RenderedTransferFrame({
    required this.index,
    required this.encodedData,
    required this.pngBytes,
  }) : imageProvider = MemoryImage(pngBytes);

  final int index;
  final String encodedData;
  final Uint8List pngBytes;
  final ImageProvider imageProvider;
}
