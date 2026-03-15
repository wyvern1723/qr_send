import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/utils/formatters.dart';
import '../controller/receiver_controller.dart';
import '../services/scanner_capability_service.dart';
import '../widgets/desktop_camera_scanner.dart';
import '../widgets/scanner_overlay.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  late final ReceiverController _controller;
  final MobileScannerController _scannerController = MobileScannerController();
  final DesktopCameraScannerController _desktopScannerController =
      DesktopCameraScannerController();

  int _lastCompletionVersionHandled = 0;
  bool _isHandlingCompletion = false;
  ScannerType _scannerType = ScannerType.unsupported;

  @override
  void initState() {
    super.initState();
    _controller = ReceiverController()..addListener(_onControllerChanged);
    _controller.initializeScanner().then((_) {
      if (mounted) {
        setState(() {
          _scannerType = _controller.scannerType;
        });
      }
    });
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }

    if (!_isHandlingCompletion &&
        _controller.completionVersion > _lastCompletionVersionHandled &&
        _controller.completedTransfer != null) {
      _lastCompletionVersionHandled = _controller.completionVersion;
      _isHandlingCompletion = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _isHandlingCompletion = false;
          return;
        }

        await _showCompletionDialog();
        _isHandlingCompletion = false;
      });
    }

    setState(() {});
  }

  Future<void> _showCompletionDialog() async {
    final completed = _controller.completedTransfer;
    if (completed == null) {
      return;
    }

    final saveResult = await _saveCompletedTransfer(completed);

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final session = completed.session;
        final titleText = saveResult.saved
            ? 'Transfer saved'
            : saveResult.cancelled
            ? 'Transfer received'
            : 'Save failed';

        final titleColor = saveResult.saved
            ? Colors.green
            : saveResult.cancelled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error;

        final titleIcon = saveResult.saved
            ? Icons.check_circle
            : saveResult.cancelled
            ? Icons.inventory_2
            : Icons.error;

        return AlertDialog(
          title: Row(
            children: [
              Icon(titleIcon, color: titleColor),
              const SizedBox(width: 8),
              Expanded(child: Text(titleText)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.fileName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              _buildDialogInfoRow('Size', formatBytes(session.fileSize)),
              _buildDialogInfoRow(
                'Chunks',
                '${completed.receivedChunkCount}/${session.totalChunks}',
              ),
              _buildDialogInfoRow('Elapsed', completed.elapsedLabel),
              _buildDialogInfoRow('Speed', completed.averageSpeedLabel),
              _buildDialogInfoRow('Session', session.sessionId),
              if (saveResult.path != null)
                _buildDialogInfoRow('Saved to', saveResult.path!),
              const SizedBox(height: 12),
              Text(saveResult.message),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _controller.clearCompletedTransfer();
                _controller.restartTransfer();
              },
              child: const Text('Restart'),
            ),
          ],
        );
      },
    );
  }

  Future<_SaveResult> _saveCompletedTransfer(
    CompletedTransferSnapshot completed,
  ) async {
    final session = completed.session;

    try {
      final bytes = _controller.assembleReceivedFileBytes();
      final saveResultToken = await FilePicker.platform.saveFile(
        dialogTitle: 'Save received file',
        fileName: session.fileName,
        bytes: bytes,
      );

      if (saveResultToken == null || saveResultToken.isEmpty) {
        return const _SaveResult(
          saved: false,
          cancelled: true,
          message:
              'The transfer completed successfully, but the file was not saved because the save dialog was cancelled.',
        );
      }

      return _SaveResult(
        saved: true,
        path: saveResultToken,
        message:
            'The received file was assembled and handed off to the system save dialog successfully.',
      );
    } catch (error) {
      return _SaveResult(
        saved: false,
        message: 'The transfer completed, but saving failed: $error',
      );
    }
  }

  Widget _buildDialogInfoRow(String label, String value) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '$label:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        _controller.handleRawValue(rawValue);
      }
    }
  }

  void _toggleTorch() {
    _scannerController.toggleTorch();
  }

  void _switchCamera() {
    _scannerController.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    final session = _controller.session;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Receive file'),
        backgroundColor: Colors.black.withValues(alpha: 0.22),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _controller.restartTransfer,
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Restart transfer',
          ),
          if (_scannerType == ScannerType.desktopCamera)
            IconButton(
              onPressed: () {
                _desktopScannerController.showDialog(context);
              },
              icon: const Icon(Icons.photo_camera),
              tooltip: 'Select camera',
            ),
          // Only show torch and camera switch controls on mobile.
          if (_scannerType == ScannerType.mobileCamera) ...[
            IconButton(
              onPressed: _toggleTorch,
              icon: const Icon(Icons.flash_on),
              tooltip: 'Toggle torch',
            ),
            IconButton(
              onPressed: _switchCamera,
              icon: const Icon(Icons.cameraswitch),
              tooltip: 'Switch camera',
            ),
          ],
        ],
      ),
      body: !_controller.cameraSupported
          ? _buildUnavailableState(_controller.statusMessage)
          : _controller.isInitializing
          ? const Center(child: CircularProgressIndicator())
          : !_controller.cameraReady
          ? _buildUnavailableState(_controller.statusMessage)
          : _buildScannerBody(session),
    );
  }

  Widget _buildScannerBody(Object? session) {
    // Choose scanner implementation based on scanner type.
    switch (_scannerType) {
      case ScannerType.mobileCamera:
        return _buildMobileScanner(session);
      case ScannerType.desktopCamera:
        return _buildDesktopScanner(session);
      case ScannerType.unsupported:
        return _buildUnavailableState('Scanner not supported on this platform');
    }
  }

  Widget _buildMobileScanner(Object? session) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _controller.handleScannerError(error);
              });
              return _buildUnavailableState('Camera unavailable: $error');
            },
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.45),
                ],
                stops: const [0, 0.28, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ScannerOverlay(borderColor: _getBorderColor(context)),
        ),
        SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Column(children: [_buildStatusCard(context)]),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildBottomPanel(context, session),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopScanner(Object? session) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Desktop camera scanner
        Positioned.fill(
          child: DesktopCameraScanner(
            controller: _desktopScannerController,
            onDetect: (String value) {
              _controller.handleRawValue(value);
            },
            errorBuilder: (context, error) {
              return _buildUnavailableState('Camera unavailable: $error');
            },
          ),
        ),
        // Status overlays shared with mobile.
        SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Column(children: [_buildStatusCard(context)]),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildBottomPanel(context, session),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel(BuildContext context, Object? session) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_controller.session != null) _buildProgressCard(context),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildUnavailableState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Color _getBorderColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    switch (_controller.scanStatus) {
      case ReceiverScanStatus.success:
        return Colors.green;
      case ReceiverScanStatus.processing:
        return scheme.primary;
      case ReceiverScanStatus.duplicate:
        return Colors.orange;
      case ReceiverScanStatus.checksumError:
      case ReceiverScanStatus.error:
        return scheme.error;
      case ReceiverScanStatus.idle:
        return scheme.primary;
    }
  }

  IconData _getStatusIcon() {
    switch (_controller.scanStatus) {
      case ReceiverScanStatus.success:
        return Icons.check_circle;
      case ReceiverScanStatus.processing:
        return Icons.autorenew;
      case ReceiverScanStatus.duplicate:
        return Icons.repeat;
      case ReceiverScanStatus.checksumError:
      case ReceiverScanStatus.error:
        return Icons.error;
      case ReceiverScanStatus.idle:
        return Icons.qr_code_scanner;
    }
  }

  Color _getStatusContainerColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    switch (_controller.scanStatus) {
      case ReceiverScanStatus.success:
        return Colors.green.withValues(alpha: 0.18);
      case ReceiverScanStatus.processing:
        return scheme.primaryContainer.withValues(alpha: 0.92);
      case ReceiverScanStatus.duplicate:
        return Colors.orange.withValues(alpha: 0.22);
      case ReceiverScanStatus.checksumError:
      case ReceiverScanStatus.error:
        return scheme.errorContainer.withValues(alpha: 0.92);
      case ReceiverScanStatus.idle:
        return themeSurfaceColor(context).withValues(alpha: 0.92);
    }
  }

  Color _getStatusForegroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    switch (_controller.scanStatus) {
      case ReceiverScanStatus.success:
        return Colors.green.shade900;
      case ReceiverScanStatus.processing:
        return scheme.onPrimaryContainer;
      case ReceiverScanStatus.duplicate:
        return Colors.orange.shade900;
      case ReceiverScanStatus.checksumError:
      case ReceiverScanStatus.error:
        return scheme.onErrorContainer;
      case ReceiverScanStatus.idle:
        return scheme.onSurface;
    }
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: _getStatusContainerColor(context),
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(_getStatusIcon(), color: _getStatusForegroundColor(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _controller.lastScanMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _getStatusForegroundColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final session = _controller.session!;
    final theme = Theme.of(context);

    return _buildGlassCard(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.download,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.fileName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_controller.receivedCount}/${session.totalChunks}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _controller.progress,
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
                value: _controller.progressPercentageLabel,
                alignment: CrossAxisAlignment.start,
              ),
              _buildMetric(
                context: context,
                label: 'Speed',
                value: _controller.receivingSpeedLabel,
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDetailLine(
                  context: context,
                  icon: Icons.storage,
                  label: 'Size',
                  value:
                      '${formatBytes(_controller.receivedBytes)} / ${formatBytes(session.fileSize)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDetailLine(
                  context: context,
                  icon: Icons.qr_code_2,
                  label: 'Missing',
                  value: _controller.missingRangesDescription,
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
                  icon: Icons.tag,
                  label: 'Session',
                  value: _controller.sessionIdentifierLabel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDetailLine(
                  context: context,
                  icon: _controller.transferEnded
                      ? Icons.flag_circle
                      : Icons.sync,
                  label: 'Sender',
                  value: _controller.transferEnded
                      ? 'End frame reached'
                      : 'Still transmitting',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _controller.statusMessage,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({
    required BuildContext context,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 8,
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
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

  Color themeSurfaceColor(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerHighest;
  }
}

class _SaveResult {
  const _SaveResult({
    required this.saved,
    required this.message,
    this.path,
    this.cancelled = false,
  });

  final bool saved;
  final String message;
  final String? path;
  final bool cancelled;
}
