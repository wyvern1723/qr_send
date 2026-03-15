import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../core/transfer/transfer.dart';
import '../models/rendered_transfer_frame.dart';
import '../services/frame_prerender_service.dart';

class SenderController extends ChangeNotifier {
  SenderController({
    TransferChunker? chunker,
    FrameCodecService? codec,
    FramePrerenderService? framePrerenderService,
  }) : _chunker = chunker ?? const TransferChunker(),
       _codec = codec ?? const FrameCodecService(),
       _framePrerenderService =
           framePrerenderService ?? const FramePrerenderService() {
    _frameHoldCount = _recommendedFrameHoldCount(_fps);
  }

  static const Duration _uiNotifyInterval = Duration(milliseconds: 250);
  static const Duration _headerFrameDisplayDuration = Duration(seconds: 2);
  static const double _minFps = 1.0;
  static const double _maxFps = 30.0;
  static const double _defaultFps = 3.0;
  static const double _preferredAutoBalanceFps = 3.0;
  static const double _maxAutoBalanceFpsForVeryLargeFiles = 5.0;
  static const int _veryLargeFileThresholdBytes = 20 * 1024 * 1024;
  static const int _minChunkSize = 64;
  static const int _maxChunkSize = 2000;
  static const int _defaultTargetTransferSeconds = 45;

  static const int _maxPrerenderMemoryBytes = 128 * 1024 * 1024;
  static const double _defaultPrerenderSize = 1024;

  final TransferChunker _chunker;
  final FrameCodecService _codec;
  final FramePrerenderService _framePrerenderService;

  PlatformFile? _selectedFile;
  Uint8List? _selectedBytes;
  PreparedTransfer? _preparedTransfer;
  String? _headerEncodedFrame;
  RenderedTransferFrame? _headerRenderedFrame;
  List<String> _encodedFrames = const [];
  List<RenderedTransferFrame> _renderedFrames = const [];

  final ValueNotifier<String?> _activeEncodedFrame = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<RenderedTransferFrame?> _activeRenderedFrame =
      ValueNotifier<RenderedTransferFrame?>(null);
  final ValueNotifier<int> _activeFrameIndex = ValueNotifier<int>(0);

  double _fps = _defaultFps;
  int _chunkSize = kDefaultChunkSize;
  int _targetTransferSeconds = _defaultTargetTransferSeconds;
  int _currentFrameIndex = 0;
  int _frameHoldCount = 1;
  int _currentFrameTick = 0;
  Timer? _playbackTimer;

  bool _repeatPlayback = true;
  bool _isPreparing = false;
  bool _isPlaying = false;
  bool _isHeaderWarmupActive = false;
  double _renderProgress = 0;
  String? _statusMessage;
  DateTime? _lastUiNotifyAt;
  DateTime? _playbackCompletedAt;

  int _requestedFrameCount = 0;
  int _presentedFrameCount = 0;
  final List<DateTime> _presentedFrameTimes = <DateTime>[];
  int _lastPresentedFrameIndex = -1;

  PlatformFile? get selectedFile => _selectedFile;
  Uint8List? get selectedBytes => _selectedBytes;
  PreparedTransfer? get preparedTransfer => _preparedTransfer;
  List<String> get encodedFrames => _encodedFrames;
  List<RenderedTransferFrame> get renderedFrames => _renderedFrames;
  RenderedTransferFrame? get headerRenderedFrame => _headerRenderedFrame;
  bool get hasSelection => _selectedFile != null && _selectedBytes != null;
  bool get hasPreparedTransfer =>
      _preparedTransfer != null && _encodedFrames.isNotEmpty;
  ValueListenable<String?> get activeEncodedFrameListenable =>
      _activeEncodedFrame;
  ValueListenable<RenderedTransferFrame?> get activeRenderedFrameListenable =>
      _activeRenderedFrame;
  ValueListenable<int> get activeFrameIndexListenable => _activeFrameIndex;
  double get fps => _fps;
  int get chunkSize => _chunkSize;
  int get targetTransferSeconds => _targetTransferSeconds;
  int get currentFrameIndex => _currentFrameIndex;
  bool get isPreparing => _isPreparing;
  bool get isPlaying => _isPlaying;
  bool get isRenderingFrames => _isPreparing && _encodedFrames.isNotEmpty;
  bool get isWarmupReady => isReadyToTransfer;
  double get renderProgress => _renderProgress;
  String? get statusMessage => _statusMessage;
  int get requestedFrameCount => _requestedFrameCount;
  int get presentedFrameCount => _presentedFrameCount;
  int get frameHoldCount => _frameHoldCount;
  bool get repeatPlayback => _repeatPlayback;

  bool get isLargeFile => (_selectedBytes?.length ?? 0) > 5 * 1024 * 1024;

  bool get isReadyToTransfer =>
      _renderedFrames.isNotEmpty &&
      _renderedFrames.length == _encodedFrames.length &&
      !_isPreparing;

  int get renderedFrameCount => _renderedFrames.length;

  String? get currentFrame =>
      _encodedFrames.isNotEmpty ? _encodedFrames[_currentFrameIndex] : null;

  double get transferProgress {
    if (_encodedFrames.isEmpty) {
      return 0;
    }
    return (_currentFrameIndex + 1) / _encodedFrames.length;
  }

  int get totalFrameCount => _encodedFrames.length;

  String get transferProgressLabel =>
      '${(transferProgress * 100).toStringAsFixed(1)}%';

  String get fileNameLabel => _selectedFile?.name ?? 'No file selected';

  String get fileSizeLabel {
    final bytes = _selectedBytes?.length;
    if (bytes == null) {
      return 'Unknown';
    }

    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get chunkSizeLabel => '$_chunkSize bytes';

  String get targetTransferDurationLabel =>
      _formatDuration(Duration(seconds: _targetTransferSeconds));

  String get playbackStateLabel {
    if (_isPreparing) {
      return 'Preparing';
    }
    if (_isPlaying) {
      return 'Transmitting';
    }
    if (_encodedFrames.isEmpty) {
      return 'Idle';
    }
    if (_playbackCompletedAt != null) {
      return 'Completed';
    }
    return 'Paused';
  }

  String get currentChunkIndexLabel {
    final prepared = _preparedTransfer;
    if (prepared == null || _encodedFrames.isEmpty) {
      return 'N/A';
    }

    final activeFrame = _activeFrameIndex.value;
    final endFrameIndex = _encodedFrames.length - 1;
    if (activeFrame >= endFrameIndex) {
      return '${prepared.totalChunks} / ${prepared.totalChunks}';
    }

    final headerCount = _effectiveHeaderFrameCount(prepared);
    final dataFrameIndex = (activeFrame - headerCount).clamp(
      0,
      prepared.totalChunks == 0 ? 0 : prepared.totalChunks - 1,
    );
    return '${dataFrameIndex + 1} / ${prepared.totalChunks}';
  }

  bool get isShowingHeaderFrame =>
      _isHeaderWarmupActive && _headerRenderedFrame != null;

  double get headerFrameProgress {
    if (!isShowingHeaderFrame) {
      return _playbackCompletedAt != null ? 1 : 0;
    }

    final holdTicks = _frameHoldTicksForHeaderWarmup();
    if (holdTicks <= 1) {
      return 1;
    }

    return ((_currentFrameTick + 1) / holdTicks).clamp(0, 1);
  }

  String get headerFrameProgressLabel {
    final elapsed = headerFrameElapsed;
    final target = _headerFrameDisplayDuration;
    final elapsedSeconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final targetSeconds = (target.inMilliseconds / 1000).toStringAsFixed(1);
    return '$elapsedSeconds s / $targetSeconds s';
  }

  Duration get headerFrameElapsed {
    if (!isShowingHeaderFrame) {
      return _headerFrameDisplayDuration;
    }

    final holdTicks = _frameHoldTicksForHeaderWarmup();
    if (holdTicks <= 0) {
      return Duration.zero;
    }

    final elapsedMilliseconds = ((_currentFrameTick + 1) * (1000 / _fps))
        .round()
        .clamp(0, _headerFrameDisplayDuration.inMilliseconds);
    return Duration(milliseconds: elapsedMilliseconds);
  }

  String get headerFrameStatusLabel {
    if (isShowingHeaderFrame) {
      return 'Header frame';
    }
    return 'Header completed';
  }

  String get estimatedRemainingLabel {
    if (_encodedFrames.isEmpty || !_isPlaying) {
      return _playbackCompletedAt != null ? '0s' : 'Unknown';
    }

    final remainingFrames = _encodedFrames.length - _currentFrameIndex - 1;
    final remainingSeconds = remainingFrames / _fps;
    return _formatDuration(
      Duration(milliseconds: (remainingSeconds * 1000).round()),
    );
  }

  String get estimatedTotalTransferLabel {
    if (_encodedFrames.isEmpty) {
      return 'Unknown';
    }

    final totalSeconds = _encodedFrames.length / _fps;
    return _formatDuration(
      Duration(milliseconds: (totalSeconds * 1000).round()),
    );
  }

  String get effectiveChunkRateLabel {
    final prepared = _preparedTransfer;
    if (prepared == null || _encodedFrames.isEmpty) {
      return 'Unknown';
    }

    final effectiveChunkRate =
        prepared.totalChunks / (_encodedFrames.length / _fps);
    return '${effectiveChunkRate.toStringAsFixed(1)} chunks/s';
  }

  String get uniqueChunkRateLabel => '${_fps.toStringAsFixed(1)} chunks/s';

  String get actualSendSpeedLabel {
    final bytesPerSecond = _chunkSize * actualPresentedFps;
    if (bytesPerSecond <= 0) {
      return 'Measuring...';
    }
    return _formatBytesPerSecond(bytesPerSecond);
  }

  String get actualPresentedFpsLabel {
    final value = actualPresentedFps;
    if (value <= 0) {
      return 'Measuring...';
    }
    return '${value.toStringAsFixed(1)} fps';
  }

  double get actualPresentedFps {
    if (_presentedFrameTimes.length < 2) {
      return 0;
    }

    final first = _presentedFrameTimes.first;
    final last = _presentedFrameTimes.last;
    final elapsedMs = last.difference(first).inMilliseconds;
    if (elapsedMs <= 0) {
      return 0;
    }

    return (_presentedFrameTimes.length - 1) / (elapsedMs / 1000);
  }

  String get targetFpsLabel => '${_fps.toStringAsFixed(0)} fps';

  String get warmupReadinessLabel {
    if (!hasSelection) {
      return 'No file selected';
    }
    if (_encodedFrames.isEmpty) {
      return 'Not prepared';
    }
    return '$renderedFrameCount / ${_encodedFrames.length} QR images ready';
  }

  double get chunkSizeSliderValue => _chunkSize.toDouble();

  double get targetTransferSliderValue => _targetTransferSeconds.toDouble();

  void recordFramePresented() {
    if (_currentFrameIndex == _lastPresentedFrameIndex) {
      return;
    }

    _lastPresentedFrameIndex = _currentFrameIndex;
    _presentedFrameCount += 1;
    final now = DateTime.now();
    _presentedFrameTimes.add(now);

    while (_presentedFrameTimes.length > 60) {
      _presentedFrameTimes.removeAt(0);
    }
  }

  Future<void> pickFile() async {
    _stopPlaybackInternal(updateStatus: false);

    _isPreparing = true;
    _renderProgress = 0;
    _playbackCompletedAt = null;
    _statusMessage = 'Selecting file...';
    _notifyUiIfNeeded(force: true);

    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) {
        _isPreparing = false;
        _statusMessage = 'File selection cancelled.';
        _notifyUiIfNeeded(force: true);
        return;
      }

      final file = result.files.single;
      Uint8List? bytes = file.bytes;

      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        _isPreparing = false;
        _statusMessage = 'Unable to read file bytes.';
        _notifyUiIfNeeded(force: true);
        return;
      }

      _applySelectedFile(file, bytes);
    } catch (error) {
      _isPreparing = false;
      _renderProgress = 0;
      _statusMessage = 'Failed to select file: $error';
      _notifyUiIfNeeded(force: true);
    }
  }

  Future<void> handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) {
      return;
    }

    _stopPlaybackInternal(updateStatus: false);
    _isPreparing = true;
    _renderProgress = 0;
    _playbackCompletedAt = null;
    _statusMessage = 'Reading dropped file...';
    _notifyUiIfNeeded(force: true);

    try {
      final file = files.first;
      final bytes = await file.readAsBytes();
      final platformFile = PlatformFile(
        name: file.name,
        size: bytes.length,
        bytes: bytes,
        path: file.path,
      );
      _applySelectedFile(platformFile, bytes);
    } catch (error) {
      _isPreparing = false;
      _renderProgress = 0;
      _statusMessage = 'Failed to read dropped file: $error';
      _notifyUiIfNeeded(force: true);
    }
  }

  void _applySelectedFile(PlatformFile file, Uint8List bytes) {
    _selectedFile = file;
    _selectedBytes = bytes;
    _applyAutoBalanceForCurrentSelection();
    _clearPreparedTransferState(resetSelection: false);
    _isPreparing = false;
    _renderProgress = 0;
    _statusMessage =
        'File selected. Adjust settings if needed, then press Prepare QRCodes.';
    _notifyUiIfNeeded(force: true);
  }

  void setChunkSize(double value) {
    _chunkSize = value.round().clamp(_minChunkSize, _maxChunkSize);
    _rebuildTransferForCurrentSelection(
      updateStatus:
          'Chunk size updated to $_chunkSize bytes. Press Prepare QRCodes to rebuild the transfer.',
      rebalance: false,
    );
  }

  void setTargetTransferSeconds(double value) {
    _targetTransferSeconds = value.round().clamp(10, 180);
    _rebuildTransferForCurrentSelection(
      updateStatus:
          'Target transfer time updated to $targetTransferDurationLabel. Press Prepare QRCodes to rebuild the transfer.',
      rebalance: false,
    );
  }

  void setFps(double value) {
    final wasPlaying = _isPlaying;
    final resumeFrameIndex = _currentFrameIndex;

    _fps = value.clamp(_minFps, _maxFps);
    _frameHoldCount = _recommendedFrameHoldCount(_fps);

    final wasReadyToTransfer = isReadyToTransfer;

    _stopPlaybackInternal(updateStatus: false);
    _resetPlaybackMetrics();
    _playbackCompletedAt = null;

    if (wasPlaying && wasReadyToTransfer) {
      startPlayback(startFrame: resumeFrameIndex);
      _statusMessage =
          'Playback speed updated to $targetFpsLabel and resumed from the current frame.';
      _notifyUiIfNeeded(force: true);
      return;
    }

    _statusMessage = wasReadyToTransfer
        ? 'Playback speed updated to $targetFpsLabel. Prepared QR codes remain ready.'
        : 'Playback speed updated to $targetFpsLabel.';
    _notifyUiIfNeeded(force: true);
  }

  void setRepeatPlayback(bool value) {
    _repeatPlayback = value;
    _statusMessage = value
        ? 'Repeat playback enabled. Transfer will loop continuously.'
        : 'Repeat playback disabled. Transfer will stop after one pass.';
    _notifyUiIfNeeded(force: true);
  }

  Future<void> prepareQRCodes() async {
    final bytes = _selectedBytes;
    final file = _selectedFile;
    if (bytes == null || file == null) {
      _statusMessage = 'Pick a file before preparing QR codes.';
      _notifyUiIfNeeded(force: true);
      return;
    }

    _stopPlaybackInternal(updateStatus: false);
    _resetPlaybackMetrics();
    _playbackCompletedAt = null;
    _isPreparing = true;
    _renderProgress = 0;
    _statusMessage = 'Preparing QR codes...';
    _notifyUiIfNeeded(force: true);

    try {
      await _prepareTransferForCurrentSettings(
        fileName: file.name,
        fileBytes: bytes,
      );
    } catch (error) {
      _isPreparing = false;
      _renderProgress = 0;
      _statusMessage = 'Failed to prepare QR codes: $error';
      _notifyUiIfNeeded(force: true);
    }
  }

  void startPlayback({int startFrame = 0}) {
    if (!isReadyToTransfer) {
      _statusMessage =
          'Pick a file and wait until all QR images are ready before starting.';
      _notifyUiIfNeeded(force: true);
      return;
    }

    final clampedStartFrame = startFrame.clamp(0, _encodedFrames.length - 1);
    _playbackTimer?.cancel();
    _resetPlaybackMetrics();
    _setCurrentFrameIndex(clampedStartFrame);
    _currentFrameTick = 0;
    _isPlaying = true;
    _isHeaderWarmupActive =
        _headerRenderedFrame != null && clampedStartFrame == 0;
    _playbackCompletedAt = null;

    if (_isHeaderWarmupActive) {
      _activeEncodedFrame.value = _headerEncodedFrame;
      _activeRenderedFrame.value = _headerRenderedFrame;
      _statusMessage = 'Showing header frame before data transfer.';
    } else {
      _statusMessage =
          'Transfer is playing at ${_fps.toStringAsFixed(0)} FPS with chunk size $_chunkSize bytes.';
    }
    _notifyUiIfNeeded(force: true);

    final interval = Duration(
      milliseconds: (1000 / _fps).round().clamp(1, 1000),
    );

    _playbackTimer = Timer.periodic(interval, (timer) {
      _requestedFrameCount += 1;

      if (_isHeaderWarmupActive) {
        final headerHoldTicks = _frameHoldTicksForHeaderWarmup();
        if (_currentFrameTick + 1 < headerHoldTicks) {
          _currentFrameTick += 1;
          _notifyUiIfNeeded();
          return;
        }

        _isHeaderWarmupActive = false;
        _currentFrameTick = 0;
        _setCurrentFrameIndex(clampedStartFrame);
        _statusMessage = 'Header finished. Data transfer started.';
        _notifyUiIfNeeded(force: true);
        return;
      }

      if (_currentFrameIndex >= _encodedFrames.length - 1) {
        if (_repeatPlayback) {
          _currentFrameTick = 0;
          _isHeaderWarmupActive = false;
          _setCurrentFrameIndex(0);
          _statusMessage = 'Playback loop restarted.';
          _notifyUiIfNeeded(force: true);
          return;
        }

        _isPlaying = false;
        _playbackCompletedAt = DateTime.now();
        _statusMessage =
            'Playback finished. You can restart from any frame to retransmit missing data.';
        timer.cancel();
        _notifyUiIfNeeded(force: true);
        return;
      }

      _currentFrameTick = 0;
      _setCurrentFrameIndex(_currentFrameIndex + 1);
      _notifyUiIfNeeded();
    });
  }

  void stopPlayback() {
    _stopPlaybackInternal(updateStatus: true);
  }

  void restartFromFrame(int requestedFrame) {
    if (_encodedFrames.isEmpty) {
      _statusMessage = 'Prepare a transfer before jumping to a frame.';
      _notifyUiIfNeeded(force: true);
      return;
    }

    final clampedFrame = requestedFrame.clamp(0, _encodedFrames.length - 1);
    startPlayback(startFrame: clampedFrame);
  }

  void showFrame(int requestedFrame) {
    if (_encodedFrames.isEmpty) {
      return;
    }

    final clampedFrame = requestedFrame.clamp(0, _encodedFrames.length - 1);
    _stopPlaybackInternal(updateStatus: false);
    _playbackCompletedAt = null;
    _isHeaderWarmupActive = false;
    _currentFrameTick = 0;
    _setCurrentFrameIndex(clampedFrame);
    _statusMessage = 'Showing frame ${clampedFrame + 1}.';
    _notifyUiIfNeeded(force: true);
  }

  void showPreviousFrame() {
    if (_encodedFrames.isEmpty) {
      return;
    }

    _stopPlaybackInternal(updateStatus: false);
    _playbackCompletedAt = null;
    _currentFrameTick = 0;
    _setCurrentFrameIndex(
      (_currentFrameIndex - 1).clamp(0, _encodedFrames.length - 1),
    );
    _statusMessage = 'Showing previous frame.';
    _notifyUiIfNeeded(force: true);
  }

  void showNextFrame() {
    if (_encodedFrames.isEmpty) {
      return;
    }

    _stopPlaybackInternal(updateStatus: false);
    _playbackCompletedAt = null;
    _currentFrameTick = 0;
    _setCurrentFrameIndex(
      (_currentFrameIndex + 1).clamp(0, _encodedFrames.length - 1),
    );
    _statusMessage = 'Showing next frame.';
    _notifyUiIfNeeded(force: true);
  }

  Future<void> _prepareTransferForCurrentSettings({
    required String fileName,
    required Uint8List fileBytes,
    bool wasPlaying = false,
  }) async {
    _renderProgress = 0;
    _statusMessage = 'Preparing transfer frames...';
    _notifyUiIfNeeded(force: true);

    _frameHoldCount = _recommendedFrameHoldCount(_fps);

    final preparedTransfer = _chunker.prepare(
      fileBytes: fileBytes,
      fileName: fileName,
      mimeType: null,
      chunkSize: _chunkSize,
    );

    _statusMessage = 'Encoding transfer frames...';
    _notifyUiIfNeeded(force: true);

    final headerEncodedFrame = _codec.encode(
      preparedTransfer
          .buildFrames(
            repeatedHeaderCount: 1,
            repeatedChunkCount: 1,
            includeEndFrame: false,
          )
          .first,
    );

    final encodedFrames = preparedTransfer
        .buildFrames(repeatedHeaderCount: 0, repeatedChunkCount: 1)
        .map(_codec.encode)
        .toList(growable: false);

    _headerEncodedFrame = headerEncodedFrame;
    _encodedFrames = encodedFrames;
    _renderedFrames = const [];
    _activeEncodedFrame.value = null;
    _activeRenderedFrame.value = null;

    final estimatedPrerenderBytes = _estimatePrerenderMemoryBytes(
      frameCount: encodedFrames.length + 1,
    );
    if (estimatedPrerenderBytes > _maxPrerenderMemoryBytes) {
      _preparedTransfer = preparedTransfer;
      _isPreparing = false;
      _renderProgress = 0;
      _statusMessage =
          'Transfer requires about ${_formatBytes(estimatedPrerenderBytes)} to prerender QR images. Reduce file size, increase chunk size, or shorten the transfer.';
      _notifyUiIfNeeded(force: true);
      return;
    }

    _statusMessage = 'Rendering QR images...';
    _notifyUiIfNeeded(force: true);

    final prerenderFrames = <String>[headerEncodedFrame, ...encodedFrames];
    final renderedFrames = await _framePrerenderService.renderAllFrames(
      encodedFrames: prerenderFrames,
      size: _defaultPrerenderSize,
      onProgress: (progress) {
        final prerenderFraction = progress.fraction;
        _renderProgress = prerenderFraction;
        _statusMessage =
            'Rendering QR images ${progress.completed} / ${progress.total}...';
        _notifyUiIfNeeded();
      },
    );

    _preparedTransfer = preparedTransfer;
    _headerRenderedFrame = renderedFrames.first;
    _renderedFrames = renderedFrames.skip(1).toList(growable: false);
    _resetPlaybackMetrics();
    _setCurrentFrameIndex(0);
    _isPreparing = false;
    _renderProgress = 1;
    _playbackCompletedAt = null;
    _statusMessage = wasPlaying
        ? 'Transfer rebuilt with chunk size $_chunkSize bytes and $targetFpsLabel. All QR images are ready.'
        : 'QR codes are ready. Press Start Transfer to begin.';
    _notifyUiIfNeeded(force: true);
  }

  void _rebuildTransferForCurrentSelection({
    required String updateStatus,
    required bool rebalance,
  }) {
    _stopPlaybackInternal(updateStatus: false);
    _resetPlaybackMetrics();
    _playbackCompletedAt = null;

    if (rebalance) {
      _applyAutoBalanceForCurrentSelection();
    } else {
      _rebalanceFpsForCurrentChunkSize();
    }

    _clearPreparedTransferState(resetSelection: false);
    _statusMessage = updateStatus;
    _renderProgress = 0;
    _notifyUiIfNeeded(force: true);
  }

  void _applyAutoBalanceForCurrentSelection() {
    final bytes = _selectedBytes;
    if (bytes == null || bytes.isEmpty) {
      return;
    }

    final estimatedChunks = (bytes.length / _chunkSize).ceil().clamp(
      1,
      1000000,
    );
    final estimatedFrameBudget =
        estimatedChunks + kDefaultHeaderRepeatCount + 1;
    final preferredTargetSeconds =
        (estimatedFrameBudget / _preferredAutoBalanceFps).ceil();
    _targetTransferSeconds = preferredTargetSeconds.clamp(10, 180);
    _rebalanceFpsForCurrentChunkSize();
  }

  void _rebalanceFpsForCurrentChunkSize() {
    final bytes = _selectedBytes;
    if (bytes == null || bytes.isEmpty) {
      _frameHoldCount = _recommendedFrameHoldCount(_fps);
      return;
    }

    final targetSeconds = _targetTransferSeconds.clamp(10, 180);
    final estimatedChunks = (bytes.length / _chunkSize).ceil().clamp(
      1,
      1000000,
    );
    final estimatedFrameBudget =
        estimatedChunks + kDefaultHeaderRepeatCount + 1;
    final autoBalanceFpsCap = _autoBalanceFpsCapForBytes(bytes.length);
    final desiredFps = (estimatedFrameBudget / targetSeconds).clamp(
      _minFps,
      autoBalanceFpsCap,
    );
    _fps = desiredFps;
    _frameHoldCount = _recommendedFrameHoldCount(_fps);
  }

  double _autoBalanceFpsCapForBytes(int byteLength) {
    if (byteLength >= _veryLargeFileThresholdBytes) {
      return _maxAutoBalanceFpsForVeryLargeFiles;
    }
    return _preferredAutoBalanceFps;
  }

  void _stopPlaybackInternal({required bool updateStatus}) {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    final wasPlaying = _isPlaying;
    _isPlaying = false;
    if (updateStatus && wasPlaying) {
      _statusMessage = 'Playback paused.';
    }
    _notifyUiIfNeeded(force: updateStatus && wasPlaying);
  }

  void _resetPlaybackMetrics() {
    _requestedFrameCount = 0;
    _presentedFrameCount = 0;
    _presentedFrameTimes.clear();
    _lastPresentedFrameIndex = -1;
    _currentFrameTick = 0;
  }

  void _clearPreparedTransferState({required bool resetSelection}) {
    _preparedTransfer = null;
    _headerEncodedFrame = null;
    _headerRenderedFrame = null;
    _encodedFrames = const [];
    _renderedFrames = const [];
    _currentFrameIndex = 0;
    _isHeaderWarmupActive = false;
    _activeFrameIndex.value = 0;
    _activeEncodedFrame.value = null;
    _activeRenderedFrame.value = null;
    if (resetSelection) {
      _selectedFile = null;
      _selectedBytes = null;
    }
  }

  void _setCurrentFrameIndex(int index) {
    _currentFrameIndex = index;
    _activeFrameIndex.value = index;
    if (_isHeaderWarmupActive && _headerRenderedFrame != null) {
      _activeEncodedFrame.value = _headerEncodedFrame;
      _activeRenderedFrame.value = _headerRenderedFrame;
      return;
    }
    _activeEncodedFrame.value = _encodedFrames.isEmpty
        ? null
        : _encodedFrames[index];
    _activeRenderedFrame.value = _renderedFrames.isEmpty
        ? null
        : _renderedFrames[index];
    if (_renderedFrames.isNotEmpty) {
      recordFramePresented();
    }
  }

  void _notifyUiIfNeeded({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastUiNotifyAt != null &&
        now.difference(_lastUiNotifyAt!) < _uiNotifyInterval) {
      return;
    }
    _lastUiNotifyAt = now;
    notifyListeners();
  }

  int _recommendedFrameHoldCount(double fps) {
    return fps.round().clamp(1, 30);
  }

  int _effectiveHeaderFrameCount(PreparedTransfer prepared) {
    return prepared
            .buildFrames(repeatedChunkCount: 1, includeEndFrame: false)
            .length -
        prepared.totalChunks;
  }

  int _frameHoldTicksForHeaderWarmup() {
    final tickDurationMs = (1000 / _fps).round().clamp(1, 1000);
    return (_headerFrameDisplayDuration.inMilliseconds / tickDurationMs)
        .ceil()
        .clamp(1, 1000);
  }

  int _estimatePrerenderMemoryBytes({required int frameCount}) {
    final estimatedBytesPerFrame =
        (_defaultPrerenderSize * _defaultPrerenderSize * 0.08).round();
    return frameCount * estimatedBytesPerFrame;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatBytesPerSecond(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
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
    _playbackTimer?.cancel();
    _activeEncodedFrame.dispose();
    _activeRenderedFrame.dispose();
    _activeFrameIndex.dispose();
    super.dispose();
  }
}
