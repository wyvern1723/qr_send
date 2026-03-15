import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/transfer_chunk.dart';
import '../models/transfer_frame.dart';
import '../models/transfer_session.dart';
import 'transfer_chunker.dart';
import 'transfer_integrity.dart';

const String kQrSendProtocolVersion = 'QRS1';

class FrameCodecService {
  const FrameCodecService();

  String encode(TransferFrame frame) {
    switch (frame.type) {
      case TransferFrameType.header:
        return _encodeHeader(frame.session);
      case TransferFrameType.data:
        return _encodeData(frame.session, frame.chunk!);
      case TransferFrameType.end:
        return _encodeEnd(frame.session);
    }
  }

  TransferFrame decode(String raw) {
    final parts = raw.split('|');
    if (parts.length < 3 || parts.first != kQrSendProtocolVersion) {
      throw const FormatException('Invalid QRSend frame');
    }

    final type = TransferFrameType.fromCode(parts[1]);
    switch (type) {
      case TransferFrameType.header:
        return TransferFrame.header(session: _decodeHeader(parts));
      case TransferFrameType.data:
        return _decodeData(parts);
      case TransferFrameType.end:
        return TransferFrame.end(session: _decodeEnd(parts));
    }
  }

  String _encodeHeader(TransferSession session) {
    return [
      kQrSendProtocolVersion,
      TransferFrameType.header.code,
      session.sessionId,
      _escape(session.fileName),
      session.fileSize.toString(),
      session.chunkSize.toString(),
      session.totalChunks.toString(),
      _escape(session.mimeType ?? ''),
      session.fileSha256,
    ].join('|');
  }

  String _encodeData(TransferSession session, TransferChunk chunk) {
    final payload = base64Url.encode(chunk.bytes).replaceAll('=', '');
    return [
      kQrSendProtocolVersion,
      TransferFrameType.data.code,
      session.sessionId,
      chunk.index.toString(),
      session.totalChunks.toString(),
      chunk.offset.toString(),
      chunk.length.toString(),
      chunk.checksum.toString(),
      payload,
    ].join('|');
  }

  String _encodeEnd(TransferSession session) {
    return [
      kQrSendProtocolVersion,
      TransferFrameType.end.code,
      session.sessionId,
      session.totalChunks.toString(),
      session.fileSha256,
    ].join('|');
  }

  TransferSession _decodeHeader(List<String> parts) {
    if (parts.length != 9) {
      throw const FormatException('Invalid header frame');
    }

    final mimeType = _unescape(parts[7]);
    return TransferSession(
      sessionId: parts[2],
      fileName: _unescape(parts[3]),
      fileSize: int.parse(parts[4]),
      chunkSize: int.parse(parts[5]),
      totalChunks: int.parse(parts[6]),
      mimeType: mimeType.isEmpty ? null : mimeType,
      fileSha256: parts[8],
    );
  }

  TransferFrame _decodeData(List<String> parts) {
    if (parts.length != 9) {
      throw const FormatException('Invalid data frame');
    }

    final sessionId = parts[2];
    final index = int.parse(parts[3]);
    final totalChunks = int.parse(parts[4]);
    final offset = int.parse(parts[5]);
    final payloadLength = int.parse(parts[6]);
    final checksum = int.parse(parts[7]);
    final payload = _decodeBase64Url(parts[8]);

    if (payload.length != payloadLength) {
      throw const FormatException('Payload length mismatch');
    }

    final actualChecksum = TransferIntegrity.computeChunkChecksum(payload);
    if (actualChecksum != checksum) {
      throw const FormatException('Payload checksum mismatch');
    }

    final inferredChunkSize = index == totalChunks - 1
        ? payloadLength
        : max(payloadLength, kMinimumChunkSize);

    return TransferFrame.data(
      session: TransferSession(
        sessionId: sessionId,
        fileName: '',
        fileSize: 0,
        chunkSize: inferredChunkSize,
        totalChunks: totalChunks,
        fileSha256: '',
      ),
      chunk: TransferChunk(
        index: index,
        offset: offset,
        bytes: payload,
        checksum: checksum,
      ),
    );
  }

  TransferSession _decodeEnd(List<String> parts) {
    if (parts.length != 5) {
      throw const FormatException('Invalid end frame');
    }

    return TransferSession(
      sessionId: parts[2],
      fileName: '',
      fileSize: 0,
      chunkSize: 0,
      totalChunks: int.parse(parts[3]),
      fileSha256: parts[4],
    );
  }

  Uint8List _decodeBase64Url(String value) {
    final normalized = switch (value.length % 4) {
      2 => '$value==',
      3 => '$value=',
      _ => value,
    };
    return Uint8List.fromList(base64Url.decode(normalized));
  }

  String _escape(String value) => Uri.encodeComponent(value);

  String _unescape(String value) => Uri.decodeComponent(value);
}
