import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../controller/sender_controller.dart';
import 'sender_transfer_screen.dart';

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  late final SenderController _controller;
  bool _isDropActive = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _controller = SenderController()..addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openTransferScreen() {
    if (!_controller.isReadyToTransfer || _controller.isPlaying) {
      return;
    }

    _controller.startPlayback();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SenderTransferScreen(controller: _controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prepared = _controller.preparedTransfer;
    final session = prepared?.session;

    final Widget content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _controller.isPreparing
                      ? null
                      : _controller.pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Pick file'),
                ),
                const SizedBox(width: 12),
                Text(
                  _controller.selectedFile?.name ?? 'No file selected',
                  style: theme.textTheme.titleMedium,
                ),
                if (session != null) ...[
                  const SizedBox(height: 12),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        label: 'Size',
                        value: formatBytes(session.fileSize),
                      ),
                      _StatChip(
                        label: 'Chunk size',
                        value: '${session.chunkSize} bytes',
                      ),
                      _StatChip(
                        label: 'Chunks',
                        value: session.totalChunks.toString(),
                      ),
                      _StatChip(
                        label: 'Frames',
                        value: _controller.encodedFrames.length.toString(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transfer settings', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                if (_controller.hasSelection) ...[
                  Text(
                    'Target transfer time: ${_controller.targetTransferDurationLabel}',
                    style: theme.textTheme.titleSmall,
                  ),
                  Slider(
                    value: _controller.targetTransferSliderValue,
                    min: 10,
                    max: 180,
                    divisions: 34,
                    label: _controller.targetTransferDurationLabel,
                    onChanged: _controller.isPreparing
                        ? null
                        : _controller.setTargetTransferSeconds,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  'Chunk size: ${_controller.chunkSizeLabel}',
                  style: theme.textTheme.titleSmall,
                ),
                Slider(
                  value: _controller.chunkSizeSliderValue,
                  min: 64,
                  max: 2000,
                  divisions: 220,
                  label: _controller.chunkSizeLabel,
                  onChanged: _controller.isPreparing
                      ? null
                      : _controller.setChunkSize,
                ),
                const SizedBox(height: 8),
                Text('Playback settings', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Current estimated playback time: ${_controller.estimatedTotalTransferLabel}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text('FPS: ${_controller.fps.toStringAsFixed(0)}'),
                Slider(
                  value: _controller.fps,
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: _controller.fps.toStringAsFixed(0),
                  onChanged: _controller.isPreparing
                      ? null
                      : _controller.setFps,
                ),
                if (_controller.isLargeFile) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Large file warning: transfers may take longer and require steadier scanning.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_controller.isPreparing) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preparing QRCodes', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _controller.renderProgress),
                  const SizedBox(height: 8),
                  Text(
                    '${_controller.statusMessage ?? 'Preparing transfer...'} ${(_controller.renderProgress * 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _controller.isPreparing
              ? null
              : _controller.isReadyToTransfer && !_controller.isPlaying
              ? _openTransferScreen
              : _controller.hasSelection
              ? _controller.prepareQRCodes
              : null,
          icon: Icon(
            _controller.isReadyToTransfer ? Icons.fullscreen : Icons.qr_code_2,
          ),
          label: Text(
            _controller.isReadyToTransfer
                ? 'Start transfer'
                : 'Prepare QRCodes',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );

    final Widget body = _isDesktop
        ? DropTarget(
            onDragEntered: (_) => setState(() => _isDropActive = true),
            onDragExited: (_) => setState(() => _isDropActive = false),
            onDragDone: (details) async {
              setState(() => _isDropActive = false);
              await _controller.handleDroppedFiles(details.files);
            },
            child: Stack(
              children: [
                content,
                if (_isDropActive)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Drop file to send',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : content;

    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: body,
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
