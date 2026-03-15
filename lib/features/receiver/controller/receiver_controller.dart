import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/transfer/transfer.dart';
import '../../../core/utils/formatters.dart';
import '../services/scanner_capability_service.dart';

enum ReceiverScanStatus {
  idle,
  processing,
  success,
  duplicate,
  checksumError,
  error,
}

class CompletedTransferSnapshot {
  const CompletedTransferSnapshot({
    required this.session,
    required this.receivedChunkCount,
    required this.receivedBytes,
    required this.completedAt,
    required this.elapsed,
  });

  final TransferSession session;
  final int receivedChunkCount;
  final int receivedBytes;
  final DateTime completedAt;
  final Duration elapsed;

  String get elapsedLabel {
    final totalSeconds = elapsed.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes <= 0) {
      return '${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  String get averageSpeedLabel {
    if (elapsed.inMilliseconds <= 0 || receivedBytes <= 0) {
      return '0 B/s';
    }

    final bytesPerSecond = receivedBytes / (elapsed.inMilliseconds / 1000);
    return '${formatBytes(bytesPerSecond.round())}/s';
  }
}

class ReceiverController extends ChangeNotifier {
  ReceiverController({
    FrameCodecService? codec,
    MissingRangeCalculator? missingRangeCalculator,
    ScannerCapabilityService? scannerCapabilityService,
  }) : _codec = codec ?? const FrameCodecService(),
       _missingRangeCalculator =
           missingRangeCalculator ?? const MissingRangeCalculator(),
       _scannerCapabilityService =
           scannerCapabilityService ?? const ScannerCapabilityService();

  /// Current scanner type.
  ScannerType get scannerType => _scannerType;
  ScannerType _scannerType = ScannerType.unsupported;

  static const Duration _duplicateDebounce = Duration(milliseconds: 220);
  static const Duration _statusDisplayDuration = Duration(milliseconds: 1500);

  final FrameCodecService _codec;
  final MissingRangeCalculator _missingRangeCalculator;
  final ScannerCapabilityService _scannerCapabilityService;

  TransferSession? _session;
  final Map<int, Uint8List> _receivedChunks = <int, Uint8List>{};
  final Map<String, DateTime> _recentFrameHits = <String, DateTime>{};

  String _statusMessage = 'Waiting for sender QR frames.';
  String _lastScanMessage = 'Align the sender QR code inside the scan frame.';
  bool _cameraReady = false;
  bool _cameraSupported = true;
  bool _transferEnded = false;
  bool _isInitializing = false;
  bool _isProcessing = false;
  DateTime? _receiveStartedAt;
  ReceiverScanStatus _scanStatus = ReceiverScanStatus.idle;
  Timer? _statusResetTimer;
  CompletedTransferSnapshot? _completedTransfer;
  int _completionVersion = 0;

  TransferSession? get session => _session;
  Map<int, Uint8List> get receivedChunks => Map.unmodifiable(_receivedChunks);
  String get statusMessage => _statusMessage;
  String get lastScanMessage => _lastScanMessage;
  bool get cameraReady => _cameraReady;
  bool get cameraSupported => _cameraSupported;
  bool get transferEnded => _transferEnded;
  bool get isInitializing => _isInitializing;
  bool get isProcessing => _isProcessing;
  ReceiverScanStatus get scanStatus => _scanStatus;
  CompletedTransferSnapshot? get completedTransfer => _completedTransfer;
  int get completionVersion => _completionVersion;

  int get receivedCount => _receivedChunks.length;

  int get receivedBytes => _receivedChunks.values.fold(
    0,
    (total, chunkBytes) => total + chunkBytes.length,
  );

  double get progress {
    final totalChunks = _session?.totalChunks ?? 0;
    return totalChunks == 0 ? 0.0 : receivedCount / totalChunks;
  }

  String get progressPercentageLabel =>
      '${(progress * 100).toStringAsFixed(1)}%';

  String get estimatedRemainingLabel {
    final activeSession = _session;
    final startedAt = _receiveStartedAt;
    if (activeSession == null || startedAt == null || receivedBytes <= 0) {
      return 'Unknown';
    }

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed.inMilliseconds <= 0) {
      return 'Unknown';
    }

    final bytesPerMillisecond = receivedBytes / elapsed.inMilliseconds;
    if (bytesPerMillisecond <= 0) {
      return 'Unknown';
    }

    final remainingBytes = activeSession.fileSize - receivedBytes;
    if (remainingBytes <= 0) {
      return '0s';
    }

    final remainingMs = (remainingBytes / bytesPerMillisecond).round();
    return _formatDuration(Duration(milliseconds: remainingMs));
  }

  String get receivingSpeedLabel {
    final startedAt = _receiveStartedAt;
    if (startedAt == null || receivedBytes <= 0) {
      return '0 B/s';
    }

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed.inMilliseconds <= 0) {
      return '0 B/s';
    }

    final bytesPerSecond = receivedBytes / (elapsed.inMilliseconds / 1000);
    return '${formatBytes(bytesPerSecond.round())}/s';
  }

  String get missingRangesDescription {
    final activeSession = _session;
    if (activeSession == null) {
      return 'Unknown';
    }
    return _missingRangeCalculator.describe(
      totalChunks: activeSession.totalChunks,
      receivedChunks: _receivedChunks.keys.toSet(),
    );
  }

  String get sessionIdentifierLabel => _session?.sessionId ?? 'N/A';

  Future<void> initializeScanner() async {
    _isInitializing = true;
    notifyListeners();

    final availability = await _scannerCapabilityService.initialize();
    _cameraSupported = availability.isSupported;
    _cameraReady = availability.isSupported && availability.isPermissionGranted;
    _scannerType = availability.scannerType;
    _statusMessage = availability.statusMessage;
    _lastScanMessage = availability.statusMessage;
    _isInitializing = false;
    notifyListeners();
  }

  void handleRawValue(String rawValue) {
    if (rawValue.isEmpty || _isInitializing || !_cameraReady) {
      return;
    }

    if (!_shouldProcessFrame(rawValue)) {
      _setScanFeedback(ReceiverScanStatus.duplicate, 'Repeated frame ignored.');
      return;
    }

    _isProcessing = true;
    _setScanFeedback(
      ReceiverScanStatus.processing,
      'Processing QR frame...',
      autoReset: false,
    );

    try {
      final frame = _codec.decode(rawValue);
      switch (frame.type) {
        case TransferFrameType.header:
          _applyHeader(frame.session);
          break;
        case TransferFrameType.data:
          _applyData(frame);
          break;
        case TransferFrameType.end:
          _applyEndFrame(frame.session);
          break;
      }
    } on FormatException catch (error) {
      final isChecksumIssue = error.message.contains('checksum');
      _setScanFeedback(
        isChecksumIssue
            ? ReceiverScanStatus.checksumError
            : ReceiverScanStatus.error,
        error.message,
      );
    } catch (error) {
      _setScanFeedback(
        ReceiverScanStatus.error,
        'Failed to decode QR frame: $error',
      );
    } finally {
      _isProcessing = false;
    }
  }

  void handleScannerError(Object error) {
    _cameraSupported = false;
    _cameraReady = false;
    _statusMessage = 'Unable to start camera scanner: $error';
    _lastScanMessage = _statusMessage;
    _scanStatus = ReceiverScanStatus.error;
    notifyListeners();
  }

  void restartTransfer() {
    _statusResetTimer?.cancel();
    _session = null;
    _receivedChunks.clear();
    _recentFrameHits.clear();
    _transferEnded = false;
    _receiveStartedAt = null;
    _isProcessing = false;
    _scanStatus = ReceiverScanStatus.idle;
    _statusMessage = 'Receiver reset. Ready for a new transfer.';
    _lastScanMessage = 'Point the camera at the sender screen to start again.';
    notifyListeners();
  }

  void clearCompletedTransfer() {
    _completedTransfer = null;
  }

  Uint8List assembleReceivedFileBytes() {
    final activeSession = _session;
    if (activeSession == null) {
      throw StateError('No active transfer session.');
    }

    if (receivedCount != activeSession.totalChunks) {
      throw StateError('Transfer is incomplete. Missing chunks remain.');
    }

    final orderedChunks = List<Uint8List>.generate(activeSession.totalChunks, (
      index,
    ) {
      final chunkBytes = _receivedChunks[index];
      if (chunkBytes == null) {
        throw StateError('Missing chunk ${index + 1}.');
      }
      return chunkBytes;
    });

    final totalBytes = orderedChunks.fold<int>(
      0,
      (sum, chunkBytes) => sum + chunkBytes.length,
    );

    if (totalBytes != activeSession.fileSize) {
      throw StateError(
        'Reassembled file size mismatch. Expected ${activeSession.fileSize} bytes, got $totalBytes bytes.',
      );
    }

    final output = Uint8List(totalBytes);
    var offset = 0;
    for (final chunkBytes in orderedChunks) {
      output.setRange(offset, offset + chunkBytes.length, chunkBytes);
      offset += chunkBytes.length;
    }

    return output;
  }

  void _applyHeader(TransferSession session) {
    if (_session != null && _session!.sessionId != session.sessionId) {
      _setScanFeedback(
        ReceiverScanStatus.error,
        'A file transfer is already in progress.',
      );
      return;
    }

    _session = session;
    _receiveStartedAt ??= DateTime.now();
    _transferEnded = false;
    _statusMessage =
        'Receiving file ${session.fileName} (${session.fileSize} bytes).';
    _setScanFeedback(
      ReceiverScanStatus.success,
      'File transfer started for ${session.fileName}.',
    );
  }

  void _applyData(TransferFrame frame) {
    final incomingSessionId = frame.session.sessionId;
    final chunk = frame.chunk!;
    final activeSession = _session;

    if (activeSession == null || activeSession.sessionId != incomingSessionId) {
      _setScanFeedback(
        ReceiverScanStatus.error,
        'Received data before the active file transfer was identified.',
      );
      return;
    }

    if (_receivedChunks.containsKey(chunk.index)) {
      _setScanFeedback(
        ReceiverScanStatus.duplicate,
        'Chunk ${chunk.index + 1} already captured.',
      );
      return;
    }

    _receivedChunks[chunk.index] = chunk.bytes;

    final isComplete = receivedCount == activeSession.totalChunks;
    _statusMessage = isComplete
        ? 'All file chunks received in memory. Ready for assembly.'
        : 'Received $receivedCount / ${activeSession.totalChunks} chunks for this file. Missing: $missingRangesDescription';

    _setScanFeedback(
      ReceiverScanStatus.success,
      isComplete
          ? 'All chunks captured for ${activeSession.fileName}.'
          : 'Captured chunk ${chunk.index + 1} of ${activeSession.totalChunks} for this file.',
    );

    if (isComplete) {
      _markTransferCompleted(activeSession);
    }
  }

  void _applyEndFrame(TransferSession session) {
    final activeSession = _session;
    if (activeSession == null || activeSession.sessionId != session.sessionId) {
      _setScanFeedback(
        ReceiverScanStatus.error,
        'End frame does not match the active file transfer.',
      );
      return;
    }

    _transferEnded = true;
    _statusMessage = receivedCount == activeSession.totalChunks
        ? 'End frame received and this file transfer is complete.'
        : 'End frame received. Continue scanning to fill the missing chunks for this file.';
    _setScanFeedback(
      ReceiverScanStatus.success,
      receivedCount == activeSession.totalChunks
          ? 'Sender reached the end frame. File transfer looks complete.'
          : 'Sender reached the end frame. Missing chunks remain for this file.',
    );
  }

  void _markTransferCompleted(TransferSession session) {
    final startedAt = _receiveStartedAt ?? DateTime.now();
    final completedAt = DateTime.now();

    _completedTransfer = CompletedTransferSnapshot(
      session: session,
      receivedChunkCount: receivedCount,
      receivedBytes: receivedBytes,
      completedAt: completedAt,
      elapsed: completedAt.difference(startedAt),
    );
    _completionVersion += 1;
  }

  bool _shouldProcessFrame(String rawValue) {
    final now = DateTime.now();
    final lastSeenAt = _recentFrameHits[rawValue];
    if (lastSeenAt != null && now.difference(lastSeenAt) < _duplicateDebounce) {
      return false;
    }

    _recentFrameHits[rawValue] = now;

    if (_recentFrameHits.length > 256) {
      final oldestKey = _recentFrameHits.keys.first;
      _recentFrameHits.remove(oldestKey);
    }

    return true;
  }

  void _setScanFeedback(
    ReceiverScanStatus status,
    String message, {
    bool autoReset = true,
  }) {
    _statusResetTimer?.cancel();
    _scanStatus = status;
    _lastScanMessage = message;
    notifyListeners();

    if (!autoReset || status == ReceiverScanStatus.idle) {
      return;
    }

    _statusResetTimer = Timer(_statusDisplayDuration, () {
      _scanStatus = ReceiverScanStatus.idle;
      notifyListeners();
    });
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    if (minutes <= 0) {
      return '${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  @override
  void dispose() {
    _statusResetTimer?.cancel();
    super.dispose();
  }
}
