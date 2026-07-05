import 'package:flutter/material.dart';

String normalizedPlatform(String? platform) {
  final normalized = platform?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) {
    return '';
  }
  if (normalized.contains('android')) {
    return 'android';
  }
  if (normalized == 'ios' ||
      normalized.contains('iphone') ||
      normalized.contains('ipad')) {
    return 'ios';
  }
  if (normalized.contains('windows') || normalized == 'win32') {
    return 'windows';
  }
  if (normalized.contains('mac') || normalized == 'darwin') {
    return 'macos';
  }
  if (normalized.contains('linux')) {
    return 'linux';
  }
  return normalized;
}

IconData? platformIconFor(String? platform) {
  switch (normalizedPlatform(platform)) {
    case 'android':
      return Icons.android_rounded;
    case 'ios':
      return Icons.phone_iphone_rounded;
    case 'windows':
      return Icons.window_rounded;
    case 'macos':
      return Icons.laptop_mac_rounded;
    case 'linux':
      return Icons.computer_rounded;
    default:
      return null;
  }
}
