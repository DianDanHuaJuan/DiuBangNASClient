import 'package:flutter/foundation.dart';

/// Debug-only relay diagnostics for `flutter run` terminal capture.
/// Filter with: `[RelayDiag]`
void relayDiag(String event, {Map<String, Object?> fields = const {}}) {
  if (!kDebugMode) {
    return;
  }
  final buffer = StringBuffer('[RelayDiag] $event');
  for (final entry in fields.entries) {
    buffer.write(' ${entry.key}=${entry.value}');
  }
  debugPrint(buffer.toString());
}

void relayDiagArtifactJson(String context, Map<String, dynamic>? artifact) {
  if (!kDebugMode || artifact == null) {
    return;
  }
  relayDiag(
    'artifact_json',
    fields: <String, Object?>{
      'context': context,
      'transferId': artifact['transferId'],
      'tempPath': artifact['tempPath'],
      'sealedPath': artifact['sealedPath'],
      'cleanupState': artifact['cleanupState'],
      'isSealed': artifact['isSealed'],
      'receivedBytes': artifact['receivedBytes'],
    },
  );
}
