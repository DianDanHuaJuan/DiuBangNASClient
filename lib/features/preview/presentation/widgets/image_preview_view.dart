/// 文件输入：PreviewImageSource
/// 文件职责：使用 extended_image 显示图片预览，优先使用本地缓存文件并在未命中时回退到预览图网络加载
/// 文件对外接口：ImagePreviewView
/// 文件包含：ImagePreviewView
import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/image/extended_image_cache_coordinator.dart';
import '../../domain/entities/preview_image_source.dart';

/// 输入：PreviewImageSource。
/// 职责：基于 preview 级图片来源渲染全屏预览，并在必要时回退到原图网络地址。
/// 对外接口：ImagePreviewView widget。
class ImagePreviewView extends StatefulWidget {
  final PreviewImageSource source;

  const ImagePreviewView({super.key, required this.source});

  @override
  State<ImagePreviewView> createState() => _ImagePreviewViewState();
}

class _ImagePreviewViewState extends State<ImagePreviewView>
    with AutomaticKeepAliveClientMixin {
  final ExtendedImageCacheCoordinator _cacheCoordinator =
      serviceLocator.extendedImageCacheCoordinator;

  File? _cachedFile;
  bool _didResolveCachedFile = false;
  String? _loadErrorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _resolveCachedFile();
  }

  @override
  void didUpdateWidget(covariant ImagePreviewView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final didChangeSource =
        oldWidget.source.previewUrl != widget.source.previewUrl ||
        oldWidget.source.previewCacheKey != widget.source.previewCacheKey;
    if (!didChangeSource) {
      return;
    }

    _cachedFile = null;
    _didResolveCachedFile = false;
    _loadErrorMessage = null;
    _resolveCachedFile();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(child: _buildImageContent()),
    );
  }

  Future<void> _resolveCachedFile() async {
    final previewUrl = widget.source.previewUrl;
    if (previewUrl.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cachedFile = null;
        _didResolveCachedFile = true;
        _loadErrorMessage = '预览图地址为空';
      });
      return;
    }

    final cacheKey = widget.source.previewCacheKey;
    final originalUrl = widget.source.originalUrl;
    final originalCacheKey = widget.source.originalCacheKey;

    try {
      final cachedPreviewFile = await _cacheCoordinator.getCachedFile(
        url: previewUrl,
        cacheKey: cacheKey,
      );
      if (!mounted || cacheKey != widget.source.previewCacheKey) {
        return;
      }

      if (cachedPreviewFile != null) {
        setState(() {
          _cachedFile = cachedPreviewFile;
          _didResolveCachedFile = true;
          _loadErrorMessage = null;
        });
        return;
      }

      if (widget.source.hasOriginalUrl && originalUrl != null) {
        final cachedOriginalFile = await _cacheCoordinator.getCachedFile(
          url: originalUrl,
          cacheKey: originalCacheKey,
        );
        if (!mounted || cacheKey != widget.source.previewCacheKey) {
          return;
        }
        if (cachedOriginalFile != null) {
          setState(() {
            _cachedFile = cachedOriginalFile;
            _didResolveCachedFile = true;
            _loadErrorMessage = null;
          });
          return;
        }
      }

      setState(() {
        _cachedFile = null;
        _didResolveCachedFile = true;
        _loadErrorMessage = null;
      });

      final hydratedPreviewFile = await _cacheCoordinator.cacheFile(
        url: previewUrl,
        cacheKey: cacheKey,
        headers: widget.source.headers,
      );
      if (!mounted || cacheKey != widget.source.previewCacheKey) {
        return;
      }

      setState(() {
        _cachedFile = hydratedPreviewFile;
        _didResolveCachedFile = true;
        _loadErrorMessage = null;
      });
    } catch (_) {
      if (widget.source.hasOriginalUrl && originalUrl != null) {
        try {
          final originalFile = await _cacheCoordinator.cacheFile(
            url: originalUrl,
            cacheKey: originalCacheKey,
            headers: widget.source.headers,
          );
          if (!mounted || cacheKey != widget.source.previewCacheKey) {
            return;
          }

          setState(() {
            _cachedFile = originalFile;
            _didResolveCachedFile = true;
            _loadErrorMessage = null;
          });
          return;
        } catch (_) {}
      }

      if (!mounted || cacheKey != widget.source.previewCacheKey) {
        return;
      }
      setState(() {
        _cachedFile = null;
        _didResolveCachedFile = true;
        _loadErrorMessage = '预览图加载失败，请点击重试';
      });
    }
  }

  Widget _buildImageContent() {
    if (!_didResolveCachedFile) {
      return _buildPlaceholder();
    }

    if (_cachedFile != null) {
      return _buildPreviewFileImage(_cachedFile!);
    }

    if (_loadErrorMessage != null) {
      return _buildReloadableError(
        message: _loadErrorMessage!,
        onTap: () {
          setState(() {
            _cachedFile = null;
            _didResolveCachedFile = false;
            _loadErrorMessage = null;
          });
          unawaited(_resolveCachedFile());
        },
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPreviewFileImage(File file) {
    return ExtendedImage.file(
      file,
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      clearMemoryCacheWhenDispose: false,
      imageCacheName: 'gallery-preview-file',
      initGestureConfigHandler: _buildGestureConfig,
      layoutInsets: MediaQuery.of(context).padding,
    );
  }

  Widget _buildPlaceholder() {
    if (widget.source.thumbnailData != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          ExtendedImage.memory(
            widget.source.thumbnailData!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            clearMemoryCacheWhenDispose: false,
            imageCacheName: 'gallery-placeholder',
          ),
          const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
        ],
      );
    }

    return const SizedBox.expand(
      child: Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
      ),
    );
  }

  GestureConfig _buildGestureConfig(ExtendedImageState _) {
    return GestureConfig(
      minScale: 1.0,
      animationMinScale: 0.8,
      maxScale: 4.0,
      animationMaxScale: 4.5,
      speed: 1.0,
      inertialSpeed: 100.0,
      initialScale: 1.0,
      inPageView: true,
      cacheGesture: true,
    );
  }

  Widget _buildReloadableError({
    required String message,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: _buildErrorWidget(message: message),
      ),
    );
  }

  Widget _buildErrorWidget({required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, size: 56, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
