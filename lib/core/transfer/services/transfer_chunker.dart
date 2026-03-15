import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/transfer_chunk.dart';
import '../models/transfer_frame.dart';
import '../models/transfer_session.dart';
import 'transfer_integrity.dart';

const int kMinimumChunkSize = 64;
const int kDefaultChunkSize = 1500;
const int kDefaultHeaderRepeatCount = 12;
const int kDefaultChunkRepeatCount = 2;

class TransferChunker {
  const TransferChunker();

  PreparedTransfer prepare({
    required Uint8List fileBytes,
    required String fileName,
    required String? mimeType,
    int chunkSize = kDefaultChunkSize,
  }) {
    final normalizedChunkSize = chunkSize.clamp(kMinimumChunkSize, 4096);
    final sessionId = _createSessionId();
    final fileHash = TransferIntegrity.computeFileSha256(fileBytes);
    final totalChunks = (fileBytes.length / normalizedChunkSize).ceil();

    final session = TransferSession(
      sessionId: sessionId,
      fileName: fileName,
      fileSize: fileBytes.length,
      chunkSize: normalizedChunkSize,
      totalChunks: totalChunks,
      fileSha256: fileHash,
      mimeType: mimeType,
    );

    final chunks = <TransferChunk>[];
    for (var index = 0; index < totalChunks; index++) {
      final offset = index * normalizedChunkSize;
      final end = min(offset + normalizedChunkSize, fileBytes.length);
      final bytes = Uint8List.fromList(fileBytes.sublist(offset, end));
      chunks.add(
        TransferChunk(
          index: index,
          offset: offset,
          bytes: bytes,
          checksum: TransferIntegrity.computeChunkChecksum(bytes),
        ),
      );
    }

    return PreparedTransfer(session: session, chunks: chunks);
  }

  String _createSessionId() {
    final random = Random.secure();
    final values = List<int>.generate(12, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }
}

class PreparedTransfer {
  const PreparedTransfer({required this.session, required this.chunks});

  final TransferSession session;
  final List<TransferChunk> chunks;

  int get totalChunks => chunks.length;

  List<TransferFrame> buildFrames({
    int repeatedHeaderCount = kDefaultHeaderRepeatCount,
    int repeatedChunkCount = kDefaultChunkRepeatCount,
    bool includeEndFrame = true,
  }) {
    final frames = <TransferFrame>[];

    for (var i = 0; i < repeatedHeaderCount; i++) {
      frames.add(TransferFrame.header(session: session));
    }

    for (final chunk in chunks) {
      for (var repeat = 0; repeat < repeatedChunkCount; repeat++) {
        frames.add(TransferFrame.data(session: session, chunk: chunk));
      }
    }

    if (includeEndFrame) {
      frames.add(TransferFrame.end(session: session));
    }

    return frames;
  }
}
