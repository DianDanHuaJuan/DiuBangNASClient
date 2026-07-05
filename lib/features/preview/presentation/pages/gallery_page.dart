/// 文件输入：媒体文件列表、初始索引、rootId、缩略图数据
/// 文件职责：显示全屏媒体预览，承载图片预览、视频播放与图片原图下载查看
/// 文件对外接口：GalleryPage
/// 文件包含：GalleryPage
import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/image/extended_image_cache_coordinator.dart';
import '../../../../core/realtime/realtime_session_service.dart';
import '../../../../core/widgets/offline_resource_gate.dart';
import '../../../files/domain/entities/file_entry_entity.dart';
import '../cubit/gallery_cubit.dart';
import '../cubit/gallery_original_download_state.dart';
import '../cubit/gallery_state.dart';
import '../widgets/image_preview_view.dart';
import '../widgets/video_preview_view.dart';

/// 输入：媒体文件列表、初始索引、rootId、缩略图数据。
/// 职责：承载全屏媒体预览、页面切换、预取和图片原图下载动作。
/// 对外接口：GalleryPage widget。
class GalleryPage extends StatefulWidget {
  final List<FileEntryEntity> mediaFiles;
  final int initialIndex;
  final String rootId;
  final Map<String, Uint8List> thumbnails;

  const GalleryPage({
    super.key,
    required this.mediaFiles,
    required this.initialIndex,
    required this.rootId,
    required this.thumbnails,
  });

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final ExtendedPageController _pageController;
  late final GalleryCubit _galleryCubit;
  late final ExtendedImageCacheCoordinator _imageCacheCoordinator;
  final Set<String> _prefetchedPreviewKeys = <String>{};
  bool _isVideoFullscreen = false;
  bool _isUpdatingVideoFullscreen = false;

  @override
  void initState() {
    super.initState();
    _pageController = ExtendedPageController(initialPage: widget.initialIndex);
    _imageCacheCoordinator = serviceLocator.extendedImageCacheCoordinator;
    _galleryCubit = GalleryCubit(
      loadPreviewUseCase: serviceLocator.loadPreviewUseCase,
      resolvePreviewImageSourceUseCase:
          serviceLocator.resolvePreviewImageSourceUseCase,
      resolvePreviewVideoSourceUseCase:
          serviceLocator.resolvePreviewVideoSourceUseCase,
      loadTransferTasksUseCase: serviceLocator.loadTransferTasksUseCase,
      observeTransferTasksUseCase: serviceLocator.observeTransferTasksUseCase,
      enqueueDownloadUseCase: serviceLocator.enqueueDownloadUseCase,
      buildOriginalPreviewDownloadPathUseCase:
          serviceLocator.buildOriginalPreviewDownloadPathUseCase,
      saveOriginalToPublicStorageUseCase:
          serviceLocator.saveOriginalToPublicStorageUseCase,
      mediaFiles: widget.mediaFiles,
      rootId: widget.rootId,
      initialIndex: widget.initialIndex,
      thumbnails: widget.thumbnails,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _schedulePrefetch(_galleryCubit.state);
    });
  }

  @override
  void dispose() {
    clearGestureDetailsCache();
    _pageController.dispose();
    _galleryCubit.close();
    unawaited(
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int index) {
    _galleryCubit.onPageChanged(index);
    if (_isVideoFullscreen && !widget.mediaFiles[index].isVideo) {
      unawaited(_setVideoFullscreen(false));
    }
  }

  void _close() {
    if (_isVideoFullscreen) {
      unawaited(_setVideoFullscreen(false));
      return;
    }

    Navigator.of(context).pop();
  }

  void _handlePopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop && _isVideoFullscreen) {
      unawaited(_setVideoFullscreen(false));
    }
  }

  Future<void> _setVideoFullscreen(bool isFullscreen) async {
    if (_isUpdatingVideoFullscreen || _isVideoFullscreen == isFullscreen) {
      return;
    }

    _isUpdatingVideoFullscreen = true;
    setState(() {
      _isVideoFullscreen = isFullscreen;
    });

    try {
      if (isFullscreen) {
        await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(
          const <DeviceOrientation>[],
        );
      }
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } finally {
      _isUpdatingVideoFullscreen = false;
    }
  }

  void _schedulePrefetch(GalleryState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_prefetchAroundCurrent(state));
    });
  }

  Future<void> _prefetchAroundCurrent(GalleryState state) async {
    final futures = <Future<void>>[];

    for (final index in _getPrefetchIndices(state.currentIndex, state.length)) {
      final imageSource = state.getImageSource(index);
      if (imageSource != null) {
        if (!_prefetchedPreviewKeys.add(imageSource.previewCacheKey)) {
          continue;
        }
        futures.add(
          _imageCacheCoordinator.prefetch(
            context: context,
            url: imageSource.previewUrl,
            cacheKey: imageSource.previewCacheKey,
            headers: imageSource.headers,
          ),
        );
        continue;
      }

      final videoSource = state.getVideoSource(index);
      if (videoSource == null ||
          !videoSource.hasPosterUrl ||
          videoSource.posterCacheKey == null) {
        continue;
      }
      if (!_prefetchedPreviewKeys.add(videoSource.posterCacheKey!)) {
        continue;
      }
      futures.add(
        _imageCacheCoordinator.prefetch(
          context: context,
          url: videoSource.posterUrl!,
          cacheKey: videoSource.posterCacheKey!,
          headers: videoSource.headers,
        ),
      );
    }

    if (futures.isEmpty) {
      return;
    }

    try {
      await Future.wait(futures);
    } catch (error) {
      // 预加载失败，静默处理
    }
  }

  List<int> _getPrefetchIndices(int centerIndex, int length) {
    final indices = <int>[];
    const offsets = <int>[0, 1, -1, 2, -2];

    for (final offset in offsets) {
      final candidate = centerIndex + offset;
      if (candidate < 0 || candidate >= length) {
        continue;
      }
      if (!indices.contains(candidate)) {
        indices.add(candidate);
      }
    }

    return indices;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _galleryCubit,
      child: PopScope(
        canPop: !_isVideoFullscreen,
        onPopInvokedWithResult: _handlePopInvokedWithResult,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              BlocListener<GalleryCubit, GalleryState>(
                listener: (context, state) => _schedulePrefetch(state),
                child: BlocBuilder<GalleryCubit, GalleryState>(
                  builder: (context, state) {
                    return ExtendedImageSlidePage(
                      child: ExtendedImageGesturePageView.builder(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: state.length,
                        itemBuilder: (context, index) {
                          return _GalleryMediaPage(
                            key: ValueKey<String>('gallery-page-$index'),
                            index: index,
                            file: state.getFile(index),
                            state: state,
                            cubit: _galleryCubit,
                            isVideoFullscreen: _isVideoFullscreen,
                            onFullscreenChanged: _setVideoFullscreen,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
              OfflineResourceGate(
                controller: serviceLocator.serverAvailabilityController,
                onReconnect: () =>
                    context.read<RealtimeSessionService>().reconnectNow(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryMediaPage extends StatefulWidget {
  final int index;
  final FileEntryEntity file;
  final GalleryState state;
  final GalleryCubit cubit;
  final bool isVideoFullscreen;
  final Future<void> Function(bool isFullscreen) onFullscreenChanged;

  const _GalleryMediaPage({
    super.key,
    required this.index,
    required this.file,
    required this.state,
    required this.cubit,
    required this.isVideoFullscreen,
    required this.onFullscreenChanged,
  });

  @override
  State<_GalleryMediaPage> createState() => _GalleryMediaPageState();
}

class _GalleryMediaPageState extends State<_GalleryMediaPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final previewItem = widget.state.getPreviewItem(widget.index);
    final imageSource = widget.state.getImageSource(widget.index);
    final videoSource = widget.state.getVideoSource(widget.index);
    final thumbnailData = widget.state.getThumbnail(widget.file.path);
    final isLoading = widget.state.isLoading(widget.index);

    if (isLoading && imageSource == null && videoSource == null) {
      return _buildLoadingPlaceholder(thumbnailData);
    }

    if (previewItem == null) {
      return _buildErrorWidget();
    }

    if (previewItem.isImage) {
      if (imageSource == null) {
        return _buildErrorWidget(message: '图片预览资源不可用');
      }

      final originalState = widget.state.getOriginalState(widget.index);
      final originalFile = originalState.hasLocalPath
          ? File(originalState.localPath!)
          : null;
      final showOriginal =
          originalState.isOriginalReady &&
          originalFile != null &&
          originalFile.existsSync() &&
          originalFile.lengthSync() > 0;

      return Stack(
        fit: StackFit.expand,
        children: [
          if (showOriginal)
            Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: Hero(
                    tag: imageSource.heroTag,
                    child: ImagePreviewView(source: imageSource),
                  ),
                ),
                ExtendedImage.file(
                  originalFile,
                  key: ValueKey<String>(
                    '${originalFile.path}-${originalFile.lengthSync()}',
                  ),
                  fit: BoxFit.contain,
                  mode: ExtendedImageMode.gesture,
                  clearMemoryCacheWhenDispose: false,
                  imageCacheName: 'gallery-original',
                  enableLoadState: true,
                  loadStateChanged: (state) {
                    switch (state.extendedImageLoadState) {
                      case LoadState.loading:
                        return const SizedBox.expand();
                      case LoadState.completed:
                        return state.completedWidget;
                      case LoadState.failed:
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              '原图加载失败，请返回后重试。',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                    }
                  },
                  initGestureConfigHandler: (state) {
                    return GestureConfig(
                      minScale: 1.0,
                      animationMinScale: 0.8,
                      maxScale: 5.0,
                      animationMaxScale: 5.5,
                      speed: 1.0,
                      inertialSpeed: 100.0,
                      initialScale: 1.0,
                      inPageView: true,
                      cacheGesture: true,
                    );
                  },
                  layoutInsets: MediaQuery.of(context).padding,
                ),
              ],
            )
          else
            Hero(
              tag: imageSource.heroTag,
              child: ImagePreviewView(source: imageSource),
            ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _OriginalActionButton(
                fileName: widget.file.name,
                fileSize: widget.file.size,
                state: originalState,
                onTapViewOriginal: () {
                  widget.cubit.handleOriginalAction(widget.index);
                },
                onTapSaveOriginal: () {
                  widget.cubit.handleSaveOriginal(widget.index);
                },
              ),
            ),
          ),
        ],
      );
    }

    if (previewItem.isVideo) {
      if (videoSource == null || !videoSource.hasVideoUrl) {
        return _buildErrorWidget(message: '视频预览资源不可用');
      }

      final isActivePage = widget.state.currentIndex == widget.index;
      final fullscreenMode = isActivePage && widget.isVideoFullscreen;
      final originalState = widget.state.getOriginalState(widget.index);

      return Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: videoSource.heroTag,
            child: VideoPreviewView(
              key: ValueKey<String>(
                'video-preview-${widget.index}-${isActivePage ? 'active' : 'idle'}',
              ),
              source: videoSource,
              isActive: isActivePage,
              fullscreenMode: fullscreenMode,
              onFullscreenChanged: widget.onFullscreenChanged,
            ),
          ),
          Positioned(
            bottom: 68,
            right: 16,
            child: _VideoDownloadButton(
              state: originalState,
              onTapDownload: () {
                widget.cubit.handleOriginalAction(widget.index);
              },
              onTapSaveOriginal: () {
                widget.cubit.handleSaveOriginal(widget.index);
              },
            ),
          ),
        ],
      );
    }

    return _buildUnsupportedWidget();
  }

  Widget _buildLoadingPlaceholder(Uint8List? thumbnailData) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          if (thumbnailData != null)
            Center(
              child: ExtendedImage.memory(
                thumbnailData,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                clearMemoryCacheWhenDispose: false,
                imageCacheName: 'gallery-loading-placeholder',
              ),
            ),
          const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget({String message = '加载失败'}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 48),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildUnsupportedWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 48),
          const SizedBox(height: 8),
          Text('暂不支持此类型预览', style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }
}

class _VideoDownloadButton extends StatelessWidget {
  final GalleryOriginalDownloadState state;
  final VoidCallback onTapDownload;
  final VoidCallback onTapSaveOriginal;

  const _VideoDownloadButton({
    required this.state,
    required this.onTapDownload,
    required this.onTapSaveOriginal,
  });

  bool get _canTap =>
      !state.isDownloading && !state.isSaving && !state.isSaved;

  void _handleTap() {
    if (!_canTap) {
      return;
    }
    if (state.isCached) {
      onTapSaveOriginal();
      return;
    }
    onTapDownload();
  }

  IconData _resolveIcon() {
    if (state.isSaved) {
      return Icons.check_rounded;
    }
    if (state.hasFailure) {
      return Icons.refresh_rounded;
    }
    return Icons.download_rounded;
  }

  Color _resolveIconColor() {
    if (state.isSaved) {
      return Colors.greenAccent;
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final showProgressRing = state.isDownloading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _canTap ? _handleTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showProgressRing)
                CustomPaint(
                  size: const Size(44, 44),
                  painter: _DownloadProgressRingPainter(
                    progress: state.progress.clamp(0.0, 1.0),
                  ),
                ),
              Icon(
                _resolveIcon(),
                color: _resolveIconColor(),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadProgressRingPainter extends CustomPainter {
  final double progress;

  _DownloadProgressRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 2.5;
    final radius = size.width / 2 - strokeWidth;

    final trackPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) {
      return;
    }

    final progressPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2,
      2 * 3.141592653589793 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_DownloadProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _OriginalActionButton extends StatelessWidget {
  final String fileName;
  final int fileSize;
  final GalleryOriginalDownloadState state;
  final VoidCallback onTapViewOriginal;
  final VoidCallback onTapSaveOriginal;

  const _OriginalActionButton({
    required this.fileName,
    required this.fileSize,
    required this.state,
    required this.onTapViewOriginal,
    required this.onTapSaveOriginal,
  });

  @override
  Widget build(BuildContext context) {
    final isCached = state.isCached;
    final isSaved = state.isSaved;

    if (isSaved) {
      return Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text('已下载', style: TextStyle(color: Colors.green, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    if (isCached) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: state.isSaving ? null : onTapSaveOriginal,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.isSaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(
                    Icons.download_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                const SizedBox(width: 8),
                Text(
                  state.isSaving ? '保存中...' : '下载原图',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: state.isSaving ? null : onTapViewOriginal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            children: [
              if (state.isDownloading)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: state.progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.isDownloading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    Icon(
                      state.hasFailure
                          ? Icons.refresh_rounded
                          : Icons.visibility_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    state.isDownloading
                        ? '下载中 ${(state.progress * 100).toStringAsFixed(0)}%'
                        : state.hasFailure
                        ? '重新查看原图'
                        : '查看原图 (${_formatSize(fileSize)})',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
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
