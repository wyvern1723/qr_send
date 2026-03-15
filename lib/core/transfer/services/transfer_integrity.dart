import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class TransferIntegrity {
  const TransferIntegrity._();

  static int computeChunkChecksum(Uint8List bytes) {
    var checksum = 0;
    for (final byte in bytes) {
      checksum = (checksum + byte) & 0xFFFFFFFF;
    }
    return checksum;
  }

  static String computeFileSha256(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  static bool verifyFile({
    required Uint8List bytes,
    required String expectedSha256,
  }) {
    return computeFileSha256(bytes) == expectedSha256;
  }
}
