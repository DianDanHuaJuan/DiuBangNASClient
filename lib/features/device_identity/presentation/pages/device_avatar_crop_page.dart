import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/profile/device_avatar_processor.dart';

class DeviceAvatarCropPage extends StatefulWidget {
  const DeviceAvatarCropPage({super.key, required this.sourcePath});

  final String sourcePath;

  static Future<Uint8List?> open(BuildContext context, String sourcePath) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => DeviceAvatarCropPage(sourcePath: sourcePath),
      ),
    );
  }

  @override
  State<DeviceAvatarCropPage> createState() => _DeviceAvatarCropPageState();
}

class _DeviceAvatarCropPageState extends State<DeviceAvatarCropPage> {
  final ImageEditorController _editorController = ImageEditorController();
  late final Future<String> _preparedSourceFuture;

  bool _processing = false;
  bool _editorReady = false;
  String? _preparedSourcePath;

  @override
  void initState() {
    super.initState();
    _preparedSourceFuture = DeviceAvatarProcessor.prepareEditorSource(
      widget.sourcePath,
    );
  }

  @override
  void dispose() {
    final prepared = _preparedSourcePath;
    if (prepared != null) {
      final file = File(prepared);
      if (file.existsSync()) {
        unawaited(file.delete());
      }
    }
    super.dispose();
  }

  Future<void> _confirmCrop() async {
    if (_processing || !_editorReady) {
      return;
    }
    setState(() => _processing = true);
    try {
      final bytes = await DeviceAvatarProcessor.cropFromEditor(
        _editorController,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(bytes);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像处理失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('裁切头像'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _processing ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: (_processing || !_editorReady) ? null : _confirmCrop,
            child: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('完成'),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _preparedSourceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('正在准备图片…', style: TextStyle(color: Colors.white70)),
                ],
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '图片加载失败：${snapshot.error ?? '未知错误'}',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          _preparedSourcePath ??= snapshot.data!;
          return Stack(
            fit: StackFit.expand,
            children: [
              ExtendedImage.file(
                File(_preparedSourcePath!),
                fit: BoxFit.contain,
                mode: ExtendedImageMode.editor,
                enableLoadState: true,
                cacheRawData: true,
                clearMemoryCacheWhenDispose: true,
                clearMemoryCacheIfFailed: true,
                loadStateChanged: (state) {
                  final loadState = state.extendedImageLoadState;
                  if (loadState == LoadState.completed && !_editorReady) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _editorReady = true);
                      }
                    });
                  } else if (loadState == LoadState.loading && _editorReady) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _editorReady = false);
                      }
                    });
                  }
                  return null;
                },
                initEditorConfigHandler: (state) {
                  return EditorConfig(
                    maxScale: 3.0,
                    cropRectPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 48,
                    ),
                    hitTestSize: 20,
                    initCropRectType: InitCropRectType.layoutRect,
                    cropAspectRatio: CropAspectRatios.ratio1_1,
                    controller: _editorController,
                    cornerSize: const Size(16, 3),
                    lineColor: Colors.white.withValues(alpha: 0.9),
                    cornerColor: Colors.white,
                  );
                },
              ),
              const IgnorePointer(child: _CircleCropOverlay()),
              Positioned(
                left: 24,
                right: 24,
                bottom: 24,
                child: Text(
                  _editorReady
                      ? '拖动和缩放图片，使头像位于圆形区域内'
                      : '编辑器加载中…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CircleCropOverlay extends StatelessWidget {
  const _CircleCropOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CircleCropOverlayPainter(
        overlayColor: Colors.black.withValues(alpha: 0.45),
        borderColor: Colors.white.withValues(alpha: 0.95),
      ),
    );
  }
}

class _CircleCropOverlayPainter extends CustomPainter {
  _CircleCropOverlayPainter({
    required this.overlayColor,
    required this.borderColor,
  });

  final Color overlayColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.36;

    final dimPath = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, Paint()..color = overlayColor);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
