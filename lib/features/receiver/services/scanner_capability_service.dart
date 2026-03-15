import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Scanner type used by the receiver.
enum ScannerType { mobileCamera, desktopCamera, unsupported }

class ScannerAvailability {
  const ScannerAvailability({
    required this.isSupported,
    required this.isPermissionGranted,
    required this.statusMessage,
    required this.scannerType,
  });

  final bool isSupported;
  final bool isPermissionGranted;
  final String statusMessage;
  final ScannerType scannerType;
}

class ScannerCapabilityService {
  const ScannerCapabilityService();

  bool _isMobilePlatform() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  bool _isDesktopPlatform() {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  Future<ScannerAvailability> initialize() async {
    // Handle web platform
    if (kIsWeb) {
      return const ScannerAvailability(
        isSupported: true,
        isPermissionGranted: true, // Browser handles permissions
        statusMessage:
            'Web camera ready. Point the receiver at the sender screen.',
        scannerType: ScannerType
            .desktopCamera, // Web typically uses desktop-like camera access
      );
    }

    // Handle mobile platforms
    if (_isMobilePlatform()) {
      final status = await Permission.camera.request();
      return ScannerAvailability(
        isSupported: true,
        isPermissionGranted: status.isGranted,
        statusMessage: status.isGranted
            ? 'Camera ready. Point the receiver at the sender screen.'
            : 'Camera permission is required to receive files.',
        scannerType: ScannerType.mobileCamera,
      );
    }

    // Handle desktop platforms
    if (_isDesktopPlatform()) {
      return const ScannerAvailability(
        isSupported: true,
        isPermissionGranted: true,
        statusMessage:
            'Desktop camera ready. Point the receiver at the sender screen.',
        scannerType: ScannerType.desktopCamera,
      );
    }

    // Unsupported platform
    return const ScannerAvailability(
      isSupported: false,
      isPermissionGranted: false,
      statusMessage: 'Camera scanning is not supported on this platform.',
      scannerType: ScannerType.unsupported,
    );
  }
}
