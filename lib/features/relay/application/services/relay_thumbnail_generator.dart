import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail_plugin/video_thumbnail_plugin.dart';

import '../../domain/relay_media_kind.dart';

class RelayThumbnailGenerator {
  const RelayThumbnailGenerator();

  static const int thumbnailWidth = 320;
  static const int thumbnailQuality = 70;

  Future<String?> generate({
    required String localPath,
    required String transferId,
    required String? mimeType,
  }) async {
    final kind = relayMediaKindFromMime(mimeType);
    if (kind == RelayMediaKind.other) {
      return null;
    }

    final cacheDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(cacheDir.path, 'relay_thumbnails'));
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }
    final outputPath = p.join(
      thumbDir.path,
      '${transferId}_thumb${kind == RelayMediaKind.image ? '.png' : '.jpg'}',
    );

    if (kind == RelayMediaKind.image) {
      return _generateImageThumbnail(localPath, outputPath);
    } else {
      return _generateVideoThumbnail(localPath, outputPath, transferId);
    }
  }

  Future<String?> _generateImageThumbnail(
    String sourcePath,
    String outputPath,
  ) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: thumbnailWidth,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();

      if (byteData == null) {
        return null;
      }

      final pngBytes = Uint8List.view(
        byteData.buffer,
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await File(outputPath).writeAsBytes(pngBytes);
      return outputPath;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _generateVideoThumbnail(
    String sourcePath,
    String outputPath,
    String transferId,
  ) async {
    try {
      final status = await VideoThumbnailPlugin.generateImageThumbnail(
        videoPath: sourcePath,
        thumbnailPath: outputPath,
        width: thumbnailWidth,
        height: thumbnailWidth,
        quality: thumbnailQuality,
        format: Format.jpg,
      );
      if (kDebugMode) {
        debugPrint(
          '[RelayThumb] VID-GEN transfer=$transferId ok=$status '
          'src=${sourcePath.length > 40 ? '...${sourcePath.substring(sourcePath.length - 40)}' : sourcePath} '
          'out=$outputPath',
        );
      }
      if (status) {
        return outputPath;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RelayThumb] VID-GEN-ERR transfer=$transferId err=$e');
      }
      return null;
    }
  }

  Future<void> deleteTempFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
