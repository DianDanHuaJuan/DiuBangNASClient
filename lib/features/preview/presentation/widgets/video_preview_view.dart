/// 文件输入：PreviewVideoSource
/// 文件职责：显示视频预览与播放控制，复用封面图与缩略图作为首屏占位
/// 文件对外接口：VideoPreviewView
/// 文件包含：VideoPreviewView
import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/image/extended_image_cache_coordinator.dart';
import '../../../../core/network/trusted_video_player_bridge.dart';
import '../../domain/entities/preview_strategy.dart';
import '../../domain/entities/preview_video_source.dart';

typedef VideoFullscreenChanged = Future<void> Function(bool isFullscreen);

typedef VideoPlaybackStateChanged =
    void Function(Duration position, bool isPlaying);

/// 输入：PreviewVideoSource。
/// 职责：基于视频地址、封面图和请求头渲染视频预览与播放交互。
/// 对外接口：VideoPreviewView widget。
class VideoPreviewView extends StatefulWidget {
  final PreviewVideoSource source;
  final bool isActive;
  final Duration? initialPosition;
  final bool autoPlay;
  final bool fullscreenMode;
  final VideoFullscreenChanged? onFullscreenChanged;
  final VideoPlaybackStateChanged? onPlaybackStateChanged;

  const VideoPreviewView({
    super.key,
    required this.source,
    this.isActive = true,
    this.initialPosition,
    this.autoPlay = false,
    this.fullscreenMode = false,
    this.onFullscreenChanged,
    this.onPlaybackStateChanged,
  });

  @override
  State<VideoPreviewView> createState() => _VideoPreviewViewState();
}

class _VideoPreviewViewState extends State<VideoPreviewView> {
  static const Duration _controlsAutoHideDelay = Duration(seconds: 3);
  static const Duration _completionTolerance = Duration(milliseconds: 200);
  static const Duration _deactivateDisposeDelay = Duration(milliseconds: 500);
  static const Duration _initDebounce = Duration(milliseconds: 150);
  static const int _maxDebugLogs = 200;

  final List<String> _debugLogs = <String>[];
  final ExtendedImageCacheCoordinator _cacheCoordinator =
      serviceLocator.extendedImageCacheCoordinator;
  final TrustedVideoPlayerBridge _trustedVideoPlayerBridge =
      TrustedVideoPlayerBridge();

  VideoPlayerController? _controller;
  Timer? _hideControlsTimer;
  Timer? _deferredDisposeTimer;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      unawaited(_initializePlayer());
    }
  }

  @override
  void didUpdateWidget(covariant VideoPreviewView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final didChangeVideoUrl =
        oldWidget.source.videoUrl != widget.source.videoUrl;
    final didChangeHeaders = !mapEquals(
      oldWidget.source.headers,
      widget.source.headers,
    );
    final didChangeActiveState = oldWidget.isActive != widget.isActive;
    final didChangeInitialPosition =
        oldWidget.initialPosition != widget.initialPosition;
    final didChangeAutoPlay = oldWidget.autoPlay != widget.autoPlay;
    if (!didChangeVideoUrl &&
        !didChangeHeaders &&
        !didChangeActiveState &&
        !didChangeInitialPosition &&
        !didChangeAutoPlay) {
      return;
    }

    if (didChangeVideoUrl) {
    }

    if (!widget.isActive) {
      unawaited(_deactivatePlayer());
      return;
    }

    unawaited(_initializePlayer());
  }

  @override
  void dispose() {
    _loadVersion++;
    _hideControlsTimer?.cancel();
    _deferredDisposeTimer?.cancel();
    unawaited(_disposeController());
    super.dispose();
  }

  Future<void> _deactivatePlayer() async {
    final loadVersion = ++_loadVersion;
    _hideControlsTimer?.cancel();
    _deferredDisposeTimer?.cancel();
    _deferredDisposeTimer = Timer(_deactivateDisposeDelay, () async {
      if (!mounted || loadVersion != _loadVersion) return;
      await _disposeController();
    });

    if (!mounted || loadVersion != _loadVersion) {
      return;
    }

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = null;
      _showControls = true;
    });
  }

  Future<void> _initializePlayer() async {
    final loadVersion = ++_loadVersion;
    final videoUrl = widget.source.videoUrl.trim();

    _hideControlsTimer?.cancel();
    _deferredDisposeTimer?.cancel();

    // Debounce short swipes to avoid rapid reinitialization
    await Future.delayed(_initDebounce);

    await _disposeController();

    if (!mounted || loadVersion != _loadVersion) {
      return;
    }

    if (!widget.isActive) {
      setState(() {
        _isInitialized = false;
        _hasError = false;
        _errorMessage = null;
        _showControls = true;
      });
      return;
    }

    if (videoUrl.isEmpty) {
      _appendDebugLog('视频地址为空');
      setState(() {
        _isInitialized = false;
        _hasError = true;
        _errorMessage = '视频播放地址为空';
        _showControls = true;
      });
      return;
    }

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = null;
      _showControls = true;
    });

    if (!mounted || loadVersion != _loadVersion || !widget.isActive) {
      return;
    }

    try {
      final controller = await _createVideoController(
        videoUrl: videoUrl,
        loadVersion: loadVersion,
      );
      if (controller == null) {
        return;
      }
      await _activateController(controller, loadVersion);
    } catch (error, st) {
      _appendDebugLog('控制器初始化失败：$error');
      _appendDebugLog('$st');
      if (!mounted || loadVersion != _loadVersion) {
        return;
      }

      setState(() {
        _controller = null;
        _isInitialized = false;
        _hasError = true;
        _errorMessage = '视频初始化失败：$error';
        _showControls = true;
      });
    }
  }

  Future<VideoPlayerController?> _createVideoController({
    required String videoUrl,
    required int loadVersion,
  }) async {
    if (_prefersNetworkPlayback) {
      final networkController = await _tryCreateNetworkController(
        videoUrl: videoUrl,
        loadVersion: loadVersion,
      );
      if (networkController != null) {
        unawaited(_cacheVideoFileInBackground(videoUrl));
        return networkController;
      }
    }

    _appendDebugLog('开始缓存视频文件：$videoUrl');
    final cachedVideoFile = await _cacheCoordinator.cacheFile(
      url: videoUrl,
      cacheKey: widget.source.videoCacheKey,
      headers: widget.source.headers,
    );
    if (!mounted || loadVersion != _loadVersion || !widget.isActive) {
      return null;
    }

    _appendDebugLog('使用本地缓存视频初始化：$videoUrl');
    final controller = VideoPlayerController.file(cachedVideoFile);
    await controller.initialize();
    return controller;
  }

  Future<VideoPlayerController?> _tryCreateNetworkController({
    required String videoUrl,
    required int loadVersion,
  }) async {
    VideoPlayerController? controller;
    try {
      await _trustedVideoPlayerBridge.ensureTrustForUrl(
        url: videoUrl,
        trustedServerStore: serviceLocator.trustedServerStore,
      );
      _appendDebugLog('优先尝试在线播放：$videoUrl');
      controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        httpHeaders: widget.source.headers ?? const <String, String>{},
      );
      await controller.initialize();
      if (!mounted || loadVersion != _loadVersion || !widget.isActive) {
        await controller.dispose();
        return null;
      }
      _appendDebugLog('在线播放初始化完成');
      return controller;
    } catch (error) {
      _appendDebugLog('在线播放初始化失败，回退到本地缓存：$error');
      await controller?.dispose();
      return null;
    }
  }

  Future<void> _activateController(
    VideoPlayerController controller,
    int loadVersion,
  ) async {
    if (!mounted || loadVersion != _loadVersion) {
      await controller.dispose();
      return;
    }

    _controller = controller;
    controller.addListener(_handleControllerChanged);

    final initialPosition = widget.initialPosition;
    if (initialPosition != null) {
      await controller.seekTo(
        _normalizePosition(initialPosition, controller.value.duration),
      );
    }

    if (widget.autoPlay) {
      await controller.play();
    } else {
      await controller.pause();
    }

    if (!mounted || loadVersion != _loadVersion) {
      controller.removeListener(_handleControllerChanged);
      if (identical(_controller, controller)) {
        _controller = null;
      }
      await controller.dispose();
      return;
    }

    setState(() {
      _isInitialized = true;
      _showControls = true;
    });
    _notifyPlaybackState(controller.value);
    if (widget.autoPlay) {
      _restartAutoHideTimer();
    }
    _appendDebugLog('控制器初始化完成');
  }

  Future<void> _cacheVideoFileInBackground(String videoUrl) async {
    try {
      await _cacheCoordinator.cacheFile(
        url: videoUrl,
        cacheKey: widget.source.videoCacheKey,
        headers: widget.source.headers,
      );
      _appendDebugLog('后台缓存视频完成');
    } catch (error, st) {
      _appendDebugLog('后台缓存视频失败：$error');
      _appendDebugLog('$st');
    }
  }

  bool get _prefersNetworkPlayback =>
      widget.source.strategy == PreviewStrategy.progressive ||
      widget.source.strategy == PreviewStrategy.streaming;

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) {
      return;
    }

    controller.removeListener(_handleControllerChanged);
    await controller.dispose();
  }

  void _appendDebugLog(String message) {
    if (!kDebugMode) return;
    final logEntry =
        '[VideoDebug] ${DateTime.now().toIso8601String()} $message';
    _debugLogs.insert(0, logEntry);
    if (_debugLogs.length > _maxDebugLogs) {
      _debugLogs.removeRange(_maxDebugLogs, _debugLogs.length);
    }
    debugPrint(logEntry);
  }

  void _showDebugLogs() {
    if (!mounted) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 360,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _debugLogs.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无调试日志',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _debugLogs.length,
                      itemBuilder: (context, index) {
                        final line = _debugLogs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: SelectableText(
                            line,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) {
      return;
    }

    final value = controller.value;
    if (value.hasError) {
      final nextError = value.errorDescription ?? '视频播放失败';
      if (_errorMessage != nextError || !_hasError) {
        _appendDebugLog('播放错误：$nextError');
        setState(() {
          _hasError = true;
          _errorMessage = nextError;
        });
      }
      return;
    }

    if (!value.isInitialized) {
      return;
    }

    _notifyPlaybackState(value);

    if (!value.isPlaying || _isCompleted(value)) {
      _hideControlsTimer?.cancel();
      if (!_showControls) {
        setState(() {
          _showControls = true;
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !_isInitialized) {
      return;
    }

    final value = controller.value;
    if (_isCompleted(value)) {
      await controller.seekTo(Duration.zero);
    }

    if (value.isPlaying) {
      await controller.pause();
      if (!mounted) {
        return;
      }
      _notifyPlaybackState(controller.value);
      setState(() {
        _showControls = true;
      });
      _hideControlsTimer?.cancel();
      return;
    }

    await controller.play();
    if (!mounted) {
      return;
    }
    _notifyPlaybackState(controller.value);
    setState(() {
      _showControls = true;
    });
    _restartAutoHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    final onFullscreenChanged = widget.onFullscreenChanged;
    if (_controller == null || !_isInitialized || onFullscreenChanged == null) {
      return;
    }

    await onFullscreenChanged(!widget.fullscreenMode);
  }

  void _handleSurfaceTap() {
    if (!_isInitialized) {
      return;
    }

    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _restartAutoHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _restartAutoHideTimer() {
    final controller = _controller;
    if (controller == null || !controller.value.isPlaying) {
      return;
    }

    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted) {
        return;
      }
      final currentController = _controller;
      if (currentController == null || !currentController.value.isPlaying) {
        return;
      }
      setState(() {
        _showControls = false;
      });
    });
  }

  void _notifyPlaybackState(VideoPlayerValue value) {
    if (!value.isInitialized) {
      return;
    }
    widget.onPlaybackStateChanged?.call(_safePosition(value), value.isPlaying);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return _buildInactiveView();
    }

    if (_hasError) {
      return _buildErrorView();
    }

    final controller = _controller;

    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleSurfaceTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPosterLayer(),
            if (controller != null && _isInitialized)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio > 0
                              ? value.aspectRatio
                              : 16 / 9,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      _buildControlsOverlay(value),
                    ],
                  );
                },
              )
            else
              _buildLoadingLayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildInactiveView() {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _VideoPosterLayer(source: widget.source),
          const Center(
            child: Icon(
              Icons.play_circle_outline_rounded,
              color: Colors.white30,
              size: 72,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterLayer() {
    return _VideoPosterLayer(source: widget.source);
  }

  Widget _buildLoadingLayer() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
    );
  }

  Widget _buildControlsOverlay(VideoPlayerValue value) {
    final shouldShowControls =
        _showControls || !value.isPlaying || _isCompleted(value);
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: shouldShowControls ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !shouldShowControls,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.28),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.52),
              ],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (kDebugMode)
                Positioned(
                  top: 12,
                  right: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: '查看调试日志',
                      onPressed: _showDebugLogs,
                      color: Colors.white,
                      icon: const Icon(Icons.bug_report_outlined),
                    ),
                  ),
                ),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _togglePlayback,
                    iconSize: 52,
                    color: Colors.white,
                    icon: Icon(_resolvePrimaryActionIcon(value)),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: EdgeInsets.zero,
                      colors: VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _formatDuration(_safePosition(value)),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        if (value.isBuffering)
                          const Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white70,
                                  ),
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '缓冲中',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(width: 12),
                            ],
                          ),
                        Text(
                          _formatDuration(value.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.32),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: widget.fullscreenMode ? '退出全屏' : '全屏',
                            onPressed: _toggleFullscreen,
                            color: Colors.white,
                            icon: Icon(
                              widget.fullscreenMode
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? '视频加载失败，请稍后重试。',
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_initializePlayer());
                    },
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    label: const Text(
                      '重试',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  if (kDebugMode)
                    OutlinedButton.icon(
                      onPressed: _showDebugLogs,
                      icon: const Icon(
                        Icons.bug_report_outlined,
                        color: Colors.white,
                      ),
                      label: const Text(
                        '调试日志',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _resolvePrimaryActionIcon(VideoPlayerValue value) {
    if (_isCompleted(value)) {
      return Icons.replay_rounded;
    }
    return value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
  }

  bool _isCompleted(VideoPlayerValue value) {
    if (!value.isInitialized || value.duration.inMicroseconds <= 0) {
      return false;
    }
    return value.position.compareTo(value.duration - _completionTolerance) >= 0;
  }

  Duration _safePosition(VideoPlayerValue value) {
    if (value.position.inMicroseconds < 0) {
      return Duration.zero;
    }
    if (value.duration.inMicroseconds > 0 &&
        value.position.compareTo(value.duration) > 0) {
      return value.duration;
    }
    return value.position;
  }

  Duration _normalizePosition(Duration position, Duration duration) {
    if (position.inMicroseconds < 0) {
      return Duration.zero;
    }
    if (duration.inMicroseconds > 0 && position.compareTo(duration) > 0) {
      return duration;
    }
    return position;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _VideoPosterLayer extends StatelessWidget {
  final PreviewVideoSource source;

  const _VideoPosterLayer({required this.source});

  @override
  Widget build(BuildContext context) {
    if (source.hasPosterUrl && source.posterCacheKey != null) {
      return _TrustedPosterImage(source: source);
    }

    if (source.hasThumbnailData) {
      return _buildThumbnailLayer();
    }

    return _buildPosterFallback();
  }

  Widget _buildThumbnailLayer() {
    return ExtendedImage.memory(
      source.thumbnailData!,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      clearMemoryCacheWhenDispose: false,
      imageCacheName: 'video-thumbnail-memory',
    );
  }

  Widget _buildPosterFallback() {
    return const Center(
      child: Icon(Icons.videocam_outlined, color: Colors.white54, size: 64),
    );
  }
}

class _TrustedPosterImage extends StatefulWidget {
  const _TrustedPosterImage({required this.source});

  final PreviewVideoSource source;

  @override
  State<_TrustedPosterImage> createState() => _TrustedPosterImageState();
}

class _TrustedPosterImageState extends State<_TrustedPosterImage> {
  final ExtendedImageCacheCoordinator _cacheCoordinator =
      serviceLocator.extendedImageCacheCoordinator;

  File? _cachedPosterFile;
  bool _didResolve = false;

  @override
  void initState() {
    super.initState();
    _resolvePosterFile();
  }

  @override
  void didUpdateWidget(covariant _TrustedPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.posterUrl == widget.source.posterUrl &&
        oldWidget.source.posterCacheKey == widget.source.posterCacheKey) {
      return;
    }
    _cachedPosterFile = null;
    _didResolve = false;
    _resolvePosterFile();
  }

  Future<void> _resolvePosterFile() async {
    final posterUrl = widget.source.posterUrl;
    final posterCacheKey = widget.source.posterCacheKey;
    if (posterUrl == null ||
        posterUrl.trim().isEmpty ||
        posterCacheKey == null ||
        posterCacheKey.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cachedPosterFile = null;
        _didResolve = true;
      });
      return;
    }

    try {
      final cachedFile = await _cacheCoordinator.cacheFile(
        url: posterUrl,
        cacheKey: posterCacheKey,
        headers: widget.source.headers,
      );
      if (!mounted || widget.source.posterCacheKey != posterCacheKey) {
        return;
      }
      setState(() {
        _cachedPosterFile = cachedFile;
        _didResolve = true;
      });
    } catch (_) {
      if (!mounted || widget.source.posterCacheKey != posterCacheKey) {
        return;
      }
      setState(() {
        _cachedPosterFile = null;
        _didResolve = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cachedPosterFile = _cachedPosterFile;
    if (cachedPosterFile != null) {
      return ExtendedImage.file(
        cachedPosterFile,
        fit: BoxFit.contain,
        clearMemoryCacheWhenDispose: false,
        imageCacheName: 'video-poster-file',
      );
    }
    if (widget.source.hasThumbnailData) {
      return ExtendedImage.memory(
        widget.source.thumbnailData!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        clearMemoryCacheWhenDispose: false,
        imageCacheName: 'video-thumbnail-memory',
      );
    }
    if (!_didResolve) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
      );
    }
    return const Center(
      child: Icon(Icons.videocam_outlined, color: Colors.white54, size: 64),
    );
  }
}
