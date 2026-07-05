import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DeviceAvatarProcessor {
  DeviceAvatarProcessor._();

  static const int targetMaxBytes = 30 * 1024;
  static const int outputEdge = 256;
  static const int editorMaxEdge = 1080;

  static Future<String> prepareEditorSource(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final prepared = await compute(_downscaleForEditor, bytes);
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(
      tempDir.path,
      'avatar_editor_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(tempPath).writeAsBytes(prepared, flush: true);
    return tempPath;
  }

  static Future<Uint8List> prepareFromFile(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    return prepareFromBytes(bytes);
  }

  static Future<Uint8List> prepareFromBytes(Uint8List bytes) async {
    final prepared = await compute(_prepareFromBytes, bytes);
    return prepared;
  }

  static Future<Uint8List> cropFromEditor(ImageEditorController controller) async {
    final job = _extractCropJob(controller);
    return compute(_processCropJob, job);
  }

  static AvatarCropJob _extractCropJob(ImageEditorController controller) {
    final state = controller.state;
    if (state == null) {
      throw StateError('头像裁切尚未就绪，请稍候');
    }

    final cropRect = controller.getCropRect();
    if (cropRect == null) {
      throw StateError('请先调整头像裁切区域');
    }

    final editAction = state.editAction;
    if (editAction == null) {
      throw StateError('头像裁切尚未就绪，请稍候');
    }

    var resolvedCropRect = cropRect;
    if (state.rawImageData.isNotEmpty &&
        state.widget.extendedImageState.imageProvider is ExtendedResizeImage) {
      final image = state.image;
      if (image != null && image.width > 0 && image.height > 0) {
        final decoded = img.decodeImage(state.rawImageData);
        if (decoded != null) {
          final widthRatio = decoded.width / image.width;
          final heightRatio = decoded.height / image.height;
          resolvedCropRect = Rect.fromLTRB(
            cropRect.left * widthRatio,
            cropRect.top * heightRatio,
            cropRect.right * widthRatio,
            cropRect.bottom * heightRatio,
          );
        }
      }
    }

    return AvatarCropJob(
      rawBytes: Uint8List.fromList(state.rawImageData),
      cropLeft: resolvedCropRect.left,
      cropTop: resolvedCropRect.top,
      cropWidth: resolvedCropRect.width,
      cropHeight: resolvedCropRect.height,
      rotateDegrees: editAction.rotateDegrees,
      flipHorizontal: editAction.flipY,
      needCrop: editAction.needCrop,
    );
  }

  static Uint8List encodeAvatarJpeg(img.Image image) {
    img.Image working = image;
    if (working.width != working.height) {
      final size = math.min(working.width, working.height);
      working = img.copyCrop(
        working,
        x: (working.width - size) ~/ 2,
        y: (working.height - size) ~/ 2,
        width: size,
        height: size,
      );
    }

    for (final edge in <int>[outputEdge, 192, 128, 96]) {
      final resized = edge == working.width && edge == working.height
          ? working
          : img.copyResize(
              working,
              width: edge,
              height: edge,
              interpolation: img.Interpolation.average,
            );
      for (final quality in <int>[82, 72, 62, 52, 42, 32]) {
        final bytes = Uint8List.fromList(
          img.encodeJpg(resized, quality: quality),
        );
        if (bytes.length <= targetMaxBytes) {
          return bytes;
        }
      }
    }

    final fallback = img.copyResize(
      working,
      width: 72,
      height: 72,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(fallback, quality: 28));
  }

  static img.Image _centerSquareCrop(img.Image source) {
    final size = math.min(source.width, source.height);
    return img.copyCrop(
      source,
      x: (source.width - size) ~/ 2,
      y: (source.height - size) ~/ 2,
      width: size,
      height: size,
    );
  }
}

class AvatarCropJob {
  const AvatarCropJob({
    required this.rawBytes,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    required this.rotateDegrees,
    required this.flipHorizontal,
    required this.needCrop,
  });

  final Uint8List rawBytes;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
  final double rotateDegrees;
  final bool flipHorizontal;
  final bool needCrop;
}

Uint8List _prepareFromBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw FormatException('无法读取图片，请选择 JPEG 或 PNG');
  }
  final oriented = img.bakeOrientation(decoded);
  return DeviceAvatarProcessor.encodeAvatarJpeg(
    DeviceAvatarProcessor._centerSquareCrop(oriented),
  );
}

Uint8List _downscaleForEditor(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw FormatException('无法读取图片，请选择 JPEG 或 PNG');
  }
  final oriented = img.bakeOrientation(decoded);
  final longest = math.max(oriented.width, oriented.height);
  if (longest <= DeviceAvatarProcessor.editorMaxEdge) {
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 88));
  }
  final scale = DeviceAvatarProcessor.editorMaxEdge / longest;
  final resized = img.copyResize(
    oriented,
    width: math.max(1, (oriented.width * scale).round()),
    height: math.max(1, (oriented.height * scale).round()),
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

Uint8List _processCropJob(AvatarCropJob job) {
  var decoded = img.decodeImage(job.rawBytes);
  if (decoded == null) {
    throw FormatException('无法读取图片，请选择 JPEG 或 PNG');
  }

  decoded = img.bakeOrientation(decoded);
  if (job.rotateDegrees != 0) {
    decoded = img.copyRotate(decoded, angle: job.rotateDegrees);
  }
  if (job.flipHorizontal) {
    decoded = img.flip(decoded, direction: img.FlipDirection.horizontal);
  }
  if (job.needCrop) {
    final width = math.max(1, job.cropWidth.round());
    final height = math.max(1, job.cropHeight.round());
    final left = job.cropLeft.round().clamp(0, math.max(0, decoded.width - 1)).toInt();
    final top = job.cropTop.round().clamp(0, math.max(0, decoded.height - 1)).toInt();
    final cropWidth = math.min(width, decoded.width - left).toInt();
    final cropHeight = math.min(height, decoded.height - top).toInt();
    decoded = img.copyCrop(
      decoded,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  return DeviceAvatarProcessor.encodeAvatarJpeg(decoded);
}
