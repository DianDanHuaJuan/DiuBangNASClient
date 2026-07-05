import 'dart:io';

import 'package:flutter/services.dart';

import 'trusted_server_store.dart';

class TrustedVideoPlayerBridge {
  static const MethodChannel _channel = MethodChannel(
    'flutter.io/videoPlayer/trust',
  );

  Future<void> ensureTrustForUrl({
    required String url,
    required TrustedServerStore trustedServerStore,
  }) async {
    if (!Platform.isAndroid || url.trim().isEmpty) {
      return;
    }

    final trustedServer = trustedServerStore.findByServerUrl(url);
    if (trustedServer == null) {
      return;
    }

    await _channel.invokeMethod<void>('registerTrustedServer', <String, Object?>{
      'serverUrl': url,
      'rootCaPem': trustedServer.rootCaPem,
      'leafSha256': trustedServer.leafSha256,
    });
  }
}
