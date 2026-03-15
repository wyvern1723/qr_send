import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/desktop_camera_scanner_service.dart';
import 'scanner_overlay.dart';

class DesktopCameraScannerController {
  Future<void> Function(BuildContext)? _showDialog;

  Future<void> showDialog(BuildContext context) async {
    final handler = _showDialog;
    if (handler != null) {
      await handler(context);
    }
  }
}

class DesktopCameraScanner extends StatefulWidget {
  const DesktopCameraScanner({
    super.key,
    required this.onDetect,
    this.errorBuilder,
    this.controller,
  });

  final void Function(String) onDetect;
  final Widget Function(BuildContext, Object)? errorBuilder;
  final DesktopCameraScannerController? controller;

  @override
  State<DesktopCameraScanner> createState() => _DesktopCameraScannerState();
}

class _DesktopCameraScannerState extends State<DesktopCameraScanner> {
  final DesktopCameraScannerService _scannerService =
      DesktopCameraScannerService();
  List<CameraDescription> _cameras = [];
  bool _isInitializing = true;
  bool _hasError = false;
  Object? _error;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    widget.controller?._showDialog = null;
    _scannerService.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await _scannerService.initialize();

      if (_cameras.isEmpty) {
        setState(() {
          _hasError = true;
          _error = 'No cameras available';
          _isInitializing = false;
        });
        return;
      }

      await _startScanning(_cameras.first);

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _error = e;
        _isInitializing = false;
      });
    }
  }

  Future<void> _startScanning(CameraDescription camera) async {
    await _scannerService.startScanning(
      camera: camera,
      onDetect: widget.onDetect,
      onError: (e) {
        setState(() {
          _hasError = true;
          _error = e;
        });
      },
    );
  }

  void _registerController() {
    widget.controller?._showDialog = showCameraSelectionDialog;
  }

  Future<void> showCameraSelectionDialog(BuildContext context) async {
    if (_cameras.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text('Select camera'),
          content: Text('No cameras available.'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select camera'),
        content: SizedBox(
          width: 360,
          child: RadioGroup<int>(
            groupValue: _selectedCameraIndex,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedCameraIndex = value;
              });
              _startScanning(_cameras[value]);
              Navigator.of(context).pop();
            },
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < _cameras.length; i++)
                  RadioListTile<int>(value: i, title: Text(_cameras[i].name)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _registerController();
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    if (_hasError) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!);
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Camera Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _error = null;
                    _isInitializing = true;
                  });
                  _initializeCamera();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        if (_scannerService.cameraController != null &&
            _scannerService.cameraController!.value.isInitialized)
          CameraPreview(_scannerService.cameraController!),

        // Scan area overlay
        Positioned.fill(
          child: ScannerOverlay(
            borderColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
