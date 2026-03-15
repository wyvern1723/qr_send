import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/transfer/transfer.dart';
import '../models/rendered_transfer_frame.dart';
import '../controller/sender_controller.dart';

class SenderTransferScreen extends StatefulWidget {
  const SenderTransferScreen({super.key, required this.controller});

  final SenderController controller;

  @override
  State<SenderTransferScreen> createState() => _SenderTransferScreenState();
}

class _SenderTransferScreenState extends State<SenderTransferScreen> {
  final TextEditingController _restartIndexController = TextEditingController();
  Timer? _frameSeekTimer;

  SenderController get _controller => widget.controller;

  void _stopTransferIfNeeded() {
    if (_controller.isPlaying) {
      _controller.stopPlayback();
    }
  }

  @override
  void dispose() {
    _frameSeekTimer?.cancel();
    _stopTransferIfNeeded();
    _restartIndexController.dispose();
    super.dispose();
  }

  void _restartFromFrame() {
    final requestedFrame = int.tryParse(_restartIndexController.text.trim());
    if (requestedFrame == null || requestedFrame < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid frame number (starting at 1).'),
        ),
      );
      return;
    }
    _controller.restartFromFrame(requestedFrame - 1);
  }

  void _startContinuousFrameSeek(VoidCallback action) {
    _frameSeekTimer?.cancel();
    action();
    _frameSeekTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      action();
    });
  }

  void _stopContinuousFrameSeek() {
    _frameSeekTimer?.cancel();
    _frameSeekTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final session = _controller.preparedTransfer?.session;
        final totalFrameCount = _controller.totalFrameCount;

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              _stopTransferIfNeeded();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Transfer'),
              actions: [
                GestureDetector(
                  onLongPressStart: (_) {
                    _startContinuousFrameSeek(_controller.showPreviousFrame);
                  },
                  onLongPressEnd: (_) {
                    _stopContinuousFrameSeek();
                  },
                  onLongPressCancel: _stopContinuousFrameSeek,
                  child: IconButton(
                    onPressed: _controller.showPreviousFrame,
                    icon: const Icon(Icons.navigate_before),
                    tooltip: 'Previous frame',
                  ),
                ),
                IconButton(
                  onPressed: _controller.isPlaying
                      ? _controller.stopPlayback
                      : _controller.startPlayback,
                  icon: Icon(
                    _controller.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  tooltip: _controller.isPlaying ? 'Pause' : 'Play',
                ),
                GestureDetector(
                  onLongPressStart: (_) {
                    _startContinuousFrameSeek(_controller.showNextFrame);
                  },
                  onLongPressEnd: (_) {
                    _stopContinuousFrameSeek();
                  },
                  onLongPressCancel: _stopContinuousFrameSeek,
                  child: IconButton(
                    onPressed: _controller.showNextFrame,
                    icon: const Icon(Icons.navigate_next),
                    tooltip: 'Next frame',
                  ),
                ),
                IconButton(
                  onPressed: () => _controller.restartFromFrame(0),
                  icon: const Icon(Icons.restart_alt),
                  tooltip: 'Restart',
                ),
              ],
            ),
            body: totalFrameCount == 0
                ? Center(
                    child: Text(
                      'No prepared transfer.',
                      style: theme.textTheme.titleMedium,
                    ),
                  )
                : SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        final contentPadding = EdgeInsets.symmetric(
                          horizontal: isWide ? 24 : 16,
                          vertical: 16,
                        );

                        final qrExtent = _calculateQrExtent(
                          constraints: constraints,
                          isWide: isWide,
                        );

                        final qrSection = _buildQrSection(
                          context: context,
                          qrExtent: qrExtent,
                        );

                        final infoSection = Column(
                          children: [
                            _buildTransferSummaryCard(
                              context: context,
                              session: session,
                              totalFrameCount: totalFrameCount,
                            ),
                            const SizedBox(height: 12),
                            _buildControlsCard(context),
                            const SizedBox(height: 12),
                            _buildFrameGridCard(context, totalFrameCount),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                'Keep the sender screen bright and steady so the receiver can capture the enlarged QR reliably.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        );

                        if (isWide) {
                          return Padding(
                            padding: contentPadding,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 7, child: qrSection),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 5,
                                  child: SingleChildScrollView(
                                    child: infoSection,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return SingleChildScrollView(
                          padding: contentPadding,
                          child: Column(
                            children: [
                              qrSection,
                              const SizedBox(height: 16),
                              infoSection,
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        );
      },
    );
  }

  double _calculateQrExtent({
    required BoxConstraints constraints,
    required bool isWide,
  }) {
    if (isWide) {
      return (constraints.maxHeight - 64).clamp(420.0, 820.0);
    }

    final shortest = constraints.biggest.shortestSide;
    return (shortest - 32).clamp(320.0, 680.0);
  }

  Widget _buildQrSection({
    required BuildContext context,
    required double qrExtent,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(
              width: qrExtent,
              // height: qrExtent,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: RepaintBoundary(
                  child: ValueListenableBuilder<RenderedTransferFrame?>(
                    valueListenable: _controller.activeRenderedFrameListenable,
                    builder: (context, renderedFrame, _) {
                      if (renderedFrame == null) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return Image(
                        image: renderedFrame.imageProvider,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.none,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransferSummaryCard({
    required BuildContext context,
    required TransferSession? session,
    required int totalFrameCount,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: _controller.activeFrameIndexListenable,
              builder: (context, frameIndex, _) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        _controller.fileNameLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Frame ${frameIndex + 1} / $totalFrameCount',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _controller.fileSizeLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_controller.isShowingHeaderFrame) ...[
              const SizedBox(height: 8),
              _buildHeaderProgressCard(context),
            ],
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: _controller.transferProgress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric(
                  context: context,
                  label: 'Progress',
                  value: _controller.transferProgressLabel,
                  alignment: CrossAxisAlignment.start,
                ),
                _buildMetric(
                  context: context,
                  label: 'State',
                  value: _controller.playbackStateLabel,
                  alignment: CrossAxisAlignment.center,
                ),
                _buildMetric(
                  context: context,
                  label: 'Remaining',
                  value: _controller.estimatedRemainingLabel,
                  alignment: CrossAxisAlignment.end,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildDetailLine(
                    context: context,
                    icon: Icons.flag,
                    label: 'Target FPS',
                    value: _controller.targetFpsLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailLine(
                    context: context,
                    icon: Icons.monitor,
                    label: 'Actual FPS',
                    value: _controller.actualPresentedFpsLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailLine(
                    context: context,
                    icon: Icons.speed,
                    label: 'Send Speed',
                    value: _controller.actualSendSpeedLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailLine(
                    context: context,
                    icon: Icons.sd_storage,
                    label: 'Chunk size',
                    value: _controller.chunkSizeLabel,
                  ),
                ),
              ],
            ),

            if (_controller.statusMessage != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _controller.statusMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: GestureDetector(
                      onLongPressStart: (_) {
                        _startContinuousFrameSeek(
                          _controller.showPreviousFrame,
                        );
                      },
                      onLongPressEnd: (_) {
                        _stopContinuousFrameSeek();
                      },
                      onLongPressCancel: _stopContinuousFrameSeek,
                      child: IconButton.filledTonal(
                        onPressed: _controller.showPreviousFrame,
                        icon: const Icon(Icons.navigate_before),
                        tooltip: 'Previous frame',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.tonalIcon(
                      onPressed: _controller.isPlaying
                          ? _controller.stopPlayback
                          : _controller.startPlayback,
                      icon: Icon(
                        _controller.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(_controller.isPlaying ? 'Pause' : 'Play'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: GestureDetector(
                      onLongPressStart: (_) {
                        _startContinuousFrameSeek(_controller.showNextFrame);
                      },
                      onLongPressEnd: (_) {
                        _stopContinuousFrameSeek();
                      },
                      onLongPressCancel: _stopContinuousFrameSeek,
                      child: IconButton.filledTonal(
                        onPressed: _controller.showNextFrame,
                        icon: const Icon(Icons.navigate_next),
                        tooltip: 'Next frame',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: IconButton.filledTonal(
                      onPressed: () {
                        _controller.setRepeatPlayback(
                          !_controller.repeatPlayback,
                        );
                      },
                      icon: Icon(
                        _controller.repeatPlayback
                            ? Icons.repeat
                            : Icons.repeat_one,
                      ),
                      tooltip: _controller.repeatPlayback
                          ? 'Loop playback'
                          : 'Play once',
                      color: _controller.repeatPlayback
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'FPS: ${_controller.fps.toStringAsFixed(0)}',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Slider(
              value: _controller.fps,
              min: 1,
              max: 30,
              divisions: 29,
              label: _controller.fps.toStringAsFixed(0),
              onChanged: _controller.setFps,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _restartIndexController,
                    decoration: const InputDecoration(
                      labelText: 'Restart from frame',
                      hintText: '1-based index',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _restartFromFrame,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restart'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'The QR code is intentionally maximized for scanning. Keep the sender device steady while transmitting.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameGridCard(BuildContext context, int totalFrameCount) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<int>(
          valueListenable: _controller.activeFrameIndexListenable,
          builder: (context, activeFrameIndex, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Frames', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List<Widget>.generate(totalFrameCount, (index) {
                      final isActive = index == activeFrameIndex;
                      return Material(
                        color: isActive
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _controller.showFrame(index),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                width: isActive ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderProgressCard(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _controller.headerFrameStatusLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _controller.headerFrameProgressLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _controller.headerFrameProgress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric({
    required BuildContext context,
    required String label,
    required String value,
    required CrossAxisAlignment alignment,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailLine({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: value, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
