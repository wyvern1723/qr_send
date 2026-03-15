import 'dart:typed_data';

class TransferChunk {
  const TransferChunk({
    required this.index,
    required this.offset,
    required this.bytes,
    required this.checksum,
  });

  final int index;
  final int offset;
  final Uint8List bytes;
  final int checksum;

  int get length => bytes.length;
}
