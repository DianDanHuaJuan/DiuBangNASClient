import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/device/media_storage_service.dart';
import '../../domain/relay_media_kind.dart';
import '../../../preview/presentation/pages/original_image_page.dart';

void openRelayLocalMediaPreview(
  BuildContext context, {
  required String fileName,
  required String localPath,
  required RelayMediaKind mediaKind,
  int? fileSize,
  bool isContentUri = false,
}) {
  if (!isContentUri && !File(localPath).existsSync()) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('本地文件不可用，请重新下载')));
    return;
  }

  final page = switch (mediaKind) {
    RelayMediaKind.video => RelayLocalVideoPreviewPage(
      fileName: fileName,
      localPath: localPath,
      isContentUri: isContentUri,
    ),
    RelayMediaKind.image => RelayLocalImagePreviewPage(
      fileName: fileName,
      localPath: localPath,
      fileSize: fileSize,
      isContentUri: isContentUri,
    ),
    RelayMediaKind.other => null,
  };
  if (page == null) {
    return;
  }

  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

class RelayLocalImagePreviewPage extends StatefulWidget {
  final String fileName;
  final String localPath;
  final int? fileSize;
  final bool isContentUri;

  const RelayLocalImagePreviewPage({
    super.key,
    required this.fileName,
    required this.localPath,
    this.fileSize,
    this.isContentUri = false,
  });

  @override
  State<RelayLocalImagePreviewPage> createState() =>
      _RelayLocalImagePreviewPageState();
}

class _RelayLocalImagePreviewPageState extends State<RelayLocalImagePreviewPage> {
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _openOriginal() {
    setState(() => _showOriginal = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showOriginal && !widget.isContentUri) {
      return OriginalImagePage(
        fileName: widget.fileName,
        localPath: widget.localPath,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (widget.isContentUri)
            Center(
              child: _ContentUriImagePreview(
                contentUri: widget.localPath,
              ),
            )
          else if (File(widget.localPath).existsSync())
            Center(
              child: ExtendedImage.file(
                File(widget.localPath),
                fit: BoxFit.contain,
                mode: ExtendedImageMode.gesture,
                initGestureConfigHandler: (_) {
                  return GestureConfig(
                    minScale: 1.0,
                    animationMinScale: 0.8,
                    maxScale: 4.0,
                    animationMaxScale: 4.5,
                    speed: 1.0,
                    inertialSpeed: 100.0,
                    initialScale: 1.0,
                    cacheGesture: false,
                    inPageView: false,
                  );
                },
                layoutInsets: MediaQuery.of(context).padding,
              ),
            )
          else
            const Center(
              child: Text(
                '预览文件已不可用，请重新下载。',
                style: TextStyle(color: Colors.white),
              ),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isContentUri)
                  FilledButton.icon(
                    onPressed: File(widget.localPath).existsSync()
                        ? _openOriginal
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: Text(
                      widget.fileSize == null
                          ? '查看原图'
                          : '查看原图 (${_formatSize(widget.fileSize!)})',
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  widget.fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class RelayLocalVideoPreviewPage extends StatefulWidget {
  final String fileName;
  final String localPath;
  final bool isContentUri;

  const RelayLocalVideoPreviewPage({
    super.key,
    required this.fileName,
    required this.localPath,
    this.isContentUri = false,
  });

  @override
  State<RelayLocalVideoPreviewPage> createState() =>
      _RelayLocalVideoPreviewPageState();
}

class _RelayLocalVideoPreviewPageState extends State<RelayLocalVideoPreviewPage> {
  Player? _player;
  VideoController? _videoController;
  bool _isReady = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final player = Player();
      final controller = VideoController(player);
      _player = player;
      _videoController = controller;

      player.stream.error.listen((error) {
        if (mounted) setState(() => _hasError = true);
      });
      player.stream.duration.listen((_) {
        if (mounted) setState(() => _isReady = true);
      });
      player.stream.videoParams.listen((params) {
        if (mounted && params.w != null && params.h != null) {
          setState(() => _isReady = true);
        }
      });

      final uri = widget.isContentUri
          ? widget.localPath
          : 'file://${widget.localPath}';
      await player.open(Media(uri), play: true);
      if (mounted) setState(() => _isReady = true);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  double get _aspectRatio {
    final player = _player;
    if (player == null) return 16 / 9;
    final width = player.state.width;
    final height = player.state.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 16 / 9;
  }

  Future<void> _saveToGallery(BuildContext context) async {
    try {
      await _mediaStorageService.saveFileToPublicStorage(
        fileName: widget.fileName,
        filePath: widget.localPath,
        fileType: MediaFileType.video,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('保存失败，请重试')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_hasError)
            const Center(
              child: Text(
                '视频无法播放，请重新下载。',
                style: TextStyle(color: Colors.white),
              ),
            )
          else if (_isReady && videoController != null)
            Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: Video(controller: videoController),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
          if (_isReady)
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      final player = _player;
                      if (player == null) return;
                      if (player.state.playing) {
                        player.pause();
                      } else {
                        player.play();
                      }
                      setState(() {});
                    },
                    icon: Icon(
                      (_player?.state.playing ?? false)
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isContentUri)
                  FilledButton.icon(
                    onPressed: () => _saveToGallery(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('保存到相册'),
                  ),
                const SizedBox(height: 12),
                Text(
                  widget.fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders an image from a content URI by reading bytes via platform channel.
class _ContentUriImagePreview extends StatefulWidget {
  const _ContentUriImagePreview({required this.contentUri});

  final String contentUri;

  @override
  State<_ContentUriImagePreview> createState() => _ContentUriImagePreviewState();
}

class _ContentUriImagePreviewState extends State<_ContentUriImagePreview> {
  Uint8List? _bytes;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await _mediaStorageService.readContentUriBytes(
        widget.contentUri,
      );
      if (!mounted) {
        return;
      }
      if (bytes != null) {
        setState(() => _bytes = bytes);
      } else {
        setState(() => _hasError = true);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Text(
          '无法加载预览，请重新下载。',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return ExtendedImage.memory(
      bytes,
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      initGestureConfigHandler: (_) {
        return GestureConfig(
          minScale: 1.0,
          animationMinScale: 0.8,
          maxScale: 4.0,
          animationMaxScale: 4.5,
          speed: 1.0,
          inertialSpeed: 100.0,
          initialScale: 1.0,
          cacheGesture: false,
          inPageView: false,
        );
      },
      layoutInsets: MediaQuery.of(context).padding,
    );
  }
}

final _mediaStorageService = MediaStorageService();
