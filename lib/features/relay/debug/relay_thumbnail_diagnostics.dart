import 'package:flutter/foundation.dart';

/// Structured relay thumbnail logs for `flutter run` diagnosis.
///
/// Filter terminal output with: `[RelayThumb]`
class RelayThumbnailDiagnostics {
  const RelayThumbnailDiagnostics._();

  static const _tag = '[RelayThumb]';

  /// Log a critical event. Use sparingly at key decision points only.
  static void log(String message) {
    if (!kDebugMode) return;
    debugPrint('$_tag $message');
  }
}
