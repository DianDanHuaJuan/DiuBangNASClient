/// 文件输入：PreviewVideoSource
/// 文件职责：显示视频预览与播放控制，复用封面图与缩略图作为首屏占位
/// 文件对外接口：VideoPreviewView
/// 文件包含：VideoPreviewView
///
/// 播放控件使用 media_kit 官方 MaterialVideoControls，通过
/// MaterialVideoControlsTheme 配置双击 5 秒 seek、长按 2x 倍速。
import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/image/extended_image_cache_coordinator.dart';
import '../../domain/entities/preview_video_source.dart';

typedef VideoFullscreenChanged = Future<void> Function(bool isFullscreen);

typedef VideoPlaybackStateChanged =
    void Function(Duration position, bool isPlaying);

typedef VideoDownloadRequested = void Function();

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
  final VideoDownloadRequested? onDownloadRequested;

  const VideoPreviewView({
    super.key,
    required this.source,
    this.isActive = true,
    this.initialPosition,
    this.autoPlay = false,
    this.fullscreenMode = false,
    this.onFullscreenChanged,
    this.onPlaybackStateChanged,
    this.onDownloadRequested,
  });

  @override
  State<VideoPreviewView> createState() => _VideoPreviewViewState();
}

class _VideoPreviewViewState extends State<VideoPreviewView> {
  static const Duration _deactivateDisposeDelay = Duration(milliseconds: 500);
  static const Duration _initDebounce = Duration(milliseconds: 150);
  static const int _maxDebugLogs = 200;

  /// 可选播放倍速档位
  static const List<double> _speedOptions = [0.5, 1.0, 1.5, 2.0, 3.0];

  final List<String> _debugLogs = <String>[];

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;

  Timer? _deferredDisposeTimer;
  bool _isReady = false;
  bool _hasError = false;
  String? _errorMessage;
  int _loadVersion = 0;

  /// 当前播放倍速
  double _playbackSpeed = 1.0;

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

    if (!widget.isActive) {
      unawaited(_deactivatePlayer());
      return;
    }

    unawaited(_initializePlayer());
  }

  @override
  void dispose() {
    _loadVersion++;
    _deferredDisposeTimer?.cancel();
    unawaited(_disposeController());
    super.dispose();
  }

  Future<void> _deactivatePlayer() async {
    final loadVersion = ++_loadVersion;
    _deferredDisposeTimer?.cancel();
    _deferredDisposeTimer = Timer(_deactivateDisposeDelay, () async {
      if (!mounted || loadVersion != _loadVersion) return;
      await _disposeController();
    });

    if (!mounted || loadVersion != _loadVersion) {
      return;
    }

    setState(() {
      _isReady = false;
      _hasError = false;
      _errorMessage = null;
    });
  }

  Future<void> _initializePlayer() async {
    final loadVersion = ++_loadVersion;
    final videoUrl = widget.source.videoUrl.trim();

    _deferredDisposeTimer?.cancel();

    // Debounce short swipes to avoid rapid reinitialization
    await Future.delayed(_initDebounce);

    await _disposeController();

    if (!mounted || loadVersion != _loadVersion) {
      return;
    }

    if (!widget.isActive) {
      setState(() {
        _isReady = false;
        _hasError = false;
        _errorMessage = null;
      });
      return;
    }

    if (videoUrl.isEmpty) {
      _appendDebugLog('视频地址为空');
      setState(() {
        _isReady = false;
        _hasError = true;
        _errorMessage = '视频播放地址为空';
      });
      return;
    }

    _appendDebugLog(
      'init strategy=${widget.source.strategy} '
      'host=${_safeVideoHost(videoUrl)} '
      'durationMs=${widget.source.durationMs} '
      'autoPlay=${widget.autoPlay} '
      'headerKeys=${widget.source.headers?.keys.toList() ?? const <String>[]}',
    );

    setState(() {
      _isReady = false;
      _hasError = false;
      _errorMessage = null;
    });

    if (!mounted || loadVersion != _loadVersion || !widget.isActive) {
      return;
    }

    try {
      final player = Player(
        configuration: const PlayerConfiguration(bufferSize: 128 * 1024 * 1024),
      );
      final controller = VideoController(player);

      _player = player;
      _videoController = controller;

      // 配置 TLS（自签名 HTTPS）
      await serviceLocator.mediaKitTlsProvider.configurePlayer(
        player,
        videoUrl,
      );

      // 局域网 NAS 视频缓冲配置（对齐业界标准方案）：
      // - cache-on-disk=no：禁用磁盘缓存，纯内存缓存（磁盘 I/O 是瓶颈）
      // - cache-secs 不设：用 mpv 默认（1000 小时），demuxer 始终全力预读直到
      //   填满 demuxer-max-bytes，避免设小值导致后半段减速（曾误设 15 秒导致
      //   后半段缓冲条停滞，被进度条追上）
      // - demuxer-readahead-secs=15：最小预读 15 秒保证
      // - demuxer-max-back-bytes=0：完全禁用后向缓冲，已播放 packet 立即丢弃，
      //   128MB 全给前向预读，避免后向清理不及时导致中后期前向预读停滞。
      //   回退 seek 用 HTTP Range 重新读取（局域网 <100ms，可接受）。
      // - demuxer-lavf-buffersize=4MB：增大 lavf demuxer 内部缓冲（默认过小
      //   导致大量小读取，参考 mpv issue #6802）
      // - stream-buffer-size=1MB：增大流缓冲区（默认 128KiB 太小，限制网络吞吐）
      // 配合 PlayerConfiguration.bufferSize=128MB（demuxer-max-bytes）。
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('cache-on-disk', 'no');
        await platform.setProperty('demuxer-readahead-secs', '15');
        await platform.setProperty('demuxer-max-back-bytes', '0');
        await platform.setProperty('demuxer-lavf-buffersize', '4194304');
        await platform.setProperty('stream-buffer-size', '1048576');
      }

      _subscribeStreams(player);

      // 应用当前倍速（切换视频时保持倍速）
      await player.setRate(_playbackSpeed);

      await player.open(
        Media(
          videoUrl,
          httpHeaders: widget.source.headers ?? const <String, String>{},
        ),
        play: widget.autoPlay,
      );

      if (!mounted || loadVersion != _loadVersion) {
        await _disposeController();
        return;
      }

      final initialPosition = widget.initialPosition;
      if (initialPosition != null) {
        await player.seek(
          _normalizePosition(initialPosition, _effectiveDuration()),
        );
      }

      if (!mounted || loadVersion != _loadVersion) {
        await _disposeController();
        return;
      }

      setState(() {
        _isReady = true;
      });
      _notifyPlaybackState();
      _appendDebugLog('播放器初始化完成');
    } catch (error, st) {
      _appendDebugLog('播放器初始化失败：$error');
      _appendDebugLog('$st');
      if (!mounted || loadVersion != _loadVersion) {
        return;
      }

      setState(() {
        _isReady = false;
        _hasError = true;
        _errorMessage = '视频初始化失败：$error';
      });
    }
  }

  void _subscribeStreams(Player player) {
    // 仅当外部需要播放状态回调时，才订阅 position/playing/completed 流，
    // 避免无谓的高频 position 事件触发空回调。
    if (widget.onPlaybackStateChanged != null) {
      _positionSub = player.stream.position.listen((_) {
        if (!mounted) return;
        _notifyPlaybackState();
      });
      _playingSub = player.stream.playing.listen((_) {
        if (!mounted) return;
        _notifyPlaybackState();
      });
      _completedSub = player.stream.completed.listen((_) {
        if (!mounted) return;
        _notifyPlaybackState();
      });
    }
    _errorSub = player.stream.error.listen((error) {
      if (!mounted) return;
      _appendDebugLog('播放错误：$error');
      setState(() {
        _hasError = true;
        _errorMessage = error;
      });
    });
  }

  Future<void> _disposeController() async {
    final player = _player;
    _player = null;
    _videoController = null;

    await _positionSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    await _errorSub?.cancel();
    _positionSub = null;
    _playingSub = null;
    _completedSub = null;
    _errorSub = null;

    if (player != null) {
      await player.dispose();
    }
  }

  void _appendDebugLog(String message) {
    if (!kDebugMode) return;
    final logEntry = '[VideoDiag] ${DateTime.now().toIso8601String()} $message';
    _debugLogs.insert(0, logEntry);
    if (_debugLogs.length > _maxDebugLogs) {
      _debugLogs.removeRange(_maxDebugLogs, _debugLogs.length);
    }
    // ignore: avoid_print
    print(logEntry);
  }

  String _safeVideoHost(String videoUrl) {
    try {
      return Uri.parse(videoUrl).host;
    } catch (_) {
      return '(invalid-url)';
    }
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

  Future<void> _toggleFullscreen() async {
    final onFullscreenChanged = widget.onFullscreenChanged;
    if (_player == null || !_isReady || onFullscreenChanged == null) {
      return;
    }

    await onFullscreenChanged(!widget.fullscreenMode);
  }

  void _notifyPlaybackState() {
    final player = _player;
    if (player == null) return;
    widget.onPlaybackStateChanged?.call(_safePosition(), player.state.playing);
  }

  // === 倍速播放 ===

  Future<void> _setPlaybackSpeed(double speed) async {
    final player = _player;
    if (player == null || !_isReady) {
      return;
    }
    await player.setRate(speed);
    if (!mounted) {
      return;
    }
    setState(() {
      _playbackSpeed = speed;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return _buildInactiveView();
    }

    if (_hasError) {
      return _buildErrorView();
    }

    final player = _player;
    final controller = _videoController;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildPosterLayer(),
          if (controller != null && player != null && _isReady)
            Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: _buildVideoWithControls(controller),
              ),
            )
          else
            _buildLoadingLayer(),
        ],
      ),
    );
  }

  /// 使用 media_kit 官方 MaterialVideoControls，通过 Theme 配置双击 seek 和长按倍速。
  Widget _buildVideoWithControls(VideoController controller) {
    return MaterialVideoControlsTheme(
      normal: _buildControlsTheme(),
      fullscreen: _buildControlsTheme(),
      child: Video(controller: controller),
    );
  }

  MaterialVideoControlsThemeData _buildControlsTheme() {
    return MaterialVideoControlsThemeData(
      // 双击 5 秒快进/快退
      seekOnDoubleTap: true,
      seekOnDoubleTapForwardDuration: const Duration(seconds: 5),
      seekOnDoubleTapBackwardDuration: const Duration(seconds: 5),
      // 长按 2 倍速
      speedUpOnLongPress: true,
      speedUpFactor: 2.0,
      // 控件唤起后持续可见的时间（默认 3 秒偏短，增至 5 秒）
      controlsHoverDuration: const Duration(seconds: 5),
      // 底部按钮栏：时间指示 + 倍速按钮 + 全屏按钮
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const Spacer(),
        _buildSpeedButton(),
        if (widget.onFullscreenChanged != null)
          IconButton(
            onPressed: _toggleFullscreen,
            color: Colors.white,
            icon: Icon(
              widget.fullscreenMode ? Icons.fullscreen_exit : Icons.fullscreen,
            ),
          ),
      ],
      // 进度条移到按钮栏上方（按钮栏顶 4+40=44，加 4 间隙 = 48），保持好拖
      // 注意：seekBarMargin 不影响手势盲区，盲区只由 bottomButtonBarMargin + buttonBarHeight 决定
      seekBarMargin: const EdgeInsets.only(left: 16, right: 16, bottom: 48),
      // 按钮栏贴近底部，减小 vertical 以缩小手势盲区（media_kit 硬编码底部内缩 16+vertical+buttonBarHeight）
      bottomButtonBarMargin: const EdgeInsets.only(
        left: 16,
        right: 8,
        bottom: 4,
      ),
      // 减小按钮栏高度以缩小手势盲区（IconButton 默认 40，刚好容纳）
      buttonBarHeight: 40,
      // 顶部按钮栏：调试日志按钮（仅 debug 模式）
      topButtonBar: kDebugMode
          ? [
              IconButton(
                onPressed: _showDebugLogs,
                color: Colors.white,
                icon: const Icon(Icons.bug_report_outlined),
              ),
            ]
          : const <Widget>[],
    );
  }

  /// 倍速切换按钮
  Widget _buildSpeedButton() {
    return PopupMenuButton<double>(
      tooltip: '播放倍速',
      onSelected: (speed) => unawaited(_setPlaybackSpeed(speed)),
      itemBuilder: (context) => _speedOptions
          .map(
            (speed) => PopupMenuItem<double>(
              value: speed,
              child: Row(
                children: [
                  if (speed == _playbackSpeed)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text('${_formatSpeed(speed)}x'),
                ],
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '${_formatSpeed(_playbackSpeed)}x',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  String _formatSpeed(double speed) {
    if (speed == speed.roundToDouble()) {
      return speed.toStringAsFixed(1);
    }
    return speed.toString();
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

  Duration _effectiveDuration() {
    final metaMs = widget.source.durationMs;
    if (metaMs != null && metaMs > 0) {
      return Duration(milliseconds: metaMs);
    }
    final player = _player;
    if (player != null && player.state.duration.inMicroseconds > 0) {
      return player.state.duration;
    }
    return Duration.zero;
  }

  Duration _safePosition() {
    final player = _player;
    if (player == null) return Duration.zero;
    final position = player.state.position;
    if (position.inMicroseconds < 0) {
      return Duration.zero;
    }
    final duration = _effectiveDuration();
    if (duration.inMicroseconds > 0 && position.compareTo(duration) > 0) {
      return duration;
    }
    return position;
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
