/// 文件输入：PreviewVideoSource
/// 文件职责：显示视频预览与播放控制，复用封面图与缩略图作为首屏占位
/// 文件对外接口：VideoPreviewView
/// 文件包含：VideoPreviewView
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
  static const Duration _controlsAutoHideDelay = Duration(seconds: 3);
  static const Duration _completionTolerance = Duration(milliseconds: 200);
  static const Duration _deactivateDisposeDelay = Duration(milliseconds: 500);
  static const Duration _initDebounce = Duration(milliseconds: 150);
  static const int _maxDebugLogs = 200;
  /// 可选播放倍速档位
  static const List<double> _speedOptions = [0.5, 1.0, 1.25, 1.5, 2.0];
  /// 长按临时倍速
  static const double _longPressSpeed = 2.0;
  /// 双击快进/快退步长
  static const Duration _seekStep = Duration(seconds: 5);

  final List<String> _debugLogs = <String>[];

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;

  Timer? _hideControlsTimer;
  Timer? _deferredDisposeTimer;
  bool _isReady = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  int _loadVersion = 0;
  /// 当前播放倍速
  double _playbackSpeed = 1.0;
  /// 长按期间保存的原倍速（松手恢复）
  double? _speedBeforeLongPress;
  /// 是否正在长按倍速
  bool _isLongPressing = false;
  /// 拖拽进度条期间暂存的 position（不直接 seek，松手才 seek）
  Duration? _scrubPosition;

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
      _isReady = false;
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
        _isReady = false;
        _hasError = false;
        _errorMessage = null;
        _showControls = true;
      });
      return;
    }

    if (videoUrl.isEmpty) {
      _appendDebugLog('视频地址为空');
      setState(() {
        _isReady = false;
        _hasError = true;
        _errorMessage = '视频播放地址为空';
        _showControls = true;
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
      _showControls = true;
    });

    if (!mounted || loadVersion != _loadVersion || !widget.isActive) {
      return;
    }

    try {
      final player = Player();
      final controller = VideoController(player);

      _player = player;
      _videoController = controller;

      // 配置 TLS（自签名 HTTPS）
      await serviceLocator.mediaKitTlsProvider.configurePlayer(
        player,
        videoUrl,
      );

      _subscribeStreams(player);

      // 应用当前倍速
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
        _showControls = true;
      });
      _notifyPlaybackState();
      if (widget.autoPlay) {
        _restartAutoHideTimer();
      }
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
        _showControls = true;
      });
    }
  }

  void _subscribeStreams(Player player) {
    _positionSub = player.stream.position.listen((position) {
      if (!mounted) return;
      _notifyPlaybackState();
      if (_isCompleted()) {
        _hideControlsTimer?.cancel();
        if (!_showControls) {
          setState(() => _showControls = true);
        }
      }
    });
    _durationSub = player.stream.duration.listen((_) {
      if (mounted) setState(() {});
    });
    _playingSub = player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() {});
      _notifyPlaybackState();
      if (playing) {
        _restartAutoHideTimer();
      } else {
        _hideControlsTimer?.cancel();
        if (!_showControls) {
          setState(() => _showControls = true);
        }
      }
    });
    _completedSub = player.stream.completed.listen((completed) {
      if (!mounted) return;
      if (completed) {
        setState(() => _showControls = true);
        _hideControlsTimer?.cancel();
      }
    });
    _bufferingSub = player.stream.buffering.listen((_) {
      if (mounted) setState(() {});
    });
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
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    await _bufferingSub?.cancel();
    await _errorSub?.cancel();
    _positionSub = null;
    _durationSub = null;
    _playingSub = null;
    _completedSub = null;
    _bufferingSub = null;
    _errorSub = null;

    if (player != null) {
      await player.dispose();
    }
  }

  void _appendDebugLog(String message) {
    if (!kDebugMode) return;
    final logEntry =
        '[VideoDiag] ${DateTime.now().toIso8601String()} $message';
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

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null || !_isReady) {
      return;
    }

    if (_isCompleted()) {
      await player.seek(Duration.zero);
    }

    if (player.state.playing) {
      await player.pause();
      if (!mounted) return;
      _notifyPlaybackState();
      setState(() => _showControls = true);
      _hideControlsTimer?.cancel();
      return;
    }

    await player.play();
    if (!mounted) return;
    _notifyPlaybackState();
    setState(() => _showControls = true);
    _restartAutoHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    final onFullscreenChanged = widget.onFullscreenChanged;
    if (_player == null || !_isReady || onFullscreenChanged == null) {
      return;
    }

    await onFullscreenChanged(!widget.fullscreenMode);
  }

  void _handleSurfaceTap() {
    if (!_isReady) {
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

  Widget _buildSpeedButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: PopupMenuButton<double>(
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_formatSpeed(_playbackSpeed)}x',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
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

  // === 双击快进/快退 5 秒 ===

  void _handleDoubleTapSeek(TapDownDetails details) {
    final player = _player;
    if (player == null || !_isReady) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final width = box.size.width;
    final isRightHalf = details.localPosition.dx > width / 2;

    final current = _safePosition();
    final target = isRightHalf ? current + _seekStep : current - _seekStep;
    unawaited(_seekToClamped(target));
  }

  Future<void> _seekToClamped(Duration target) async {
    final player = _player;
    if (player == null || !_isReady) {
      return;
    }
    final duration = _effectiveDuration();
    final clamped = _normalizePosition(target, duration);
    await player.seek(clamped);
  }

  // === 长按 2 倍速 ===

  void _beginLongPressSpeed() {
    final player = _player;
    if (player == null || !_isReady || _isLongPressing) {
      return;
    }
    if (_playbackSpeed != _longPressSpeed) {
      _speedBeforeLongPress = _playbackSpeed;
    } else {
      _speedBeforeLongPress = null;
    }
    _isLongPressing = true;
    unawaited(_setPlaybackSpeed(_longPressSpeed));
  }

  void _endLongPressSpeed() {
    if (!_isLongPressing) {
      return;
    }
    _isLongPressing = false;
    final restore = _speedBeforeLongPress ?? 1.0;
    _speedBeforeLongPress = null;
    unawaited(_setPlaybackSpeed(restore));
  }

  void _restartAutoHideTimer() {
    final player = _player;
    if (player == null || !player.state.playing) {
      return;
    }

    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted) {
        return;
      }
      final current = _player;
      if (current == null || !current.state.playing) {
        return;
      }
      setState(() {
        _showControls = false;
      });
    });
  }

  void _notifyPlaybackState() {
    final player = _player;
    if (player == null) return;
    widget.onPlaybackStateChanged?.call(_safePosition(), player.state.playing);
  }

  // === 进度条拖拽 ===

  void _onProgressBarDragStart() {
    _hideControlsTimer?.cancel();
    if (!_showControls) {
      setState(() => _showControls = true);
    }
  }

  void _onProgressBarDragUpdate(double ratio) {
    final duration = _effectiveDuration();
    final target = Duration(
      milliseconds: (duration.inMilliseconds * ratio).round(),
    );
    _scrubPosition = target;
    if (mounted) setState(() {});
  }

  Future<void> _onProgressBarDragEnd() async {
    final target = _scrubPosition;
    _scrubPosition = null;
    if (target != null) {
      await _seekToClamped(target);
    }
    _restartAutoHideTimer();
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleSurfaceTap,
        onDoubleTapDown: _handleDoubleTapSeek,
        onDoubleTap: () {},
        onLongPressStart: (_) => _beginLongPressSpeed(),
        onLongPressEnd: (_) => _endLongPressSpeed(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPosterLayer(),
            if (controller != null && player != null && _isReady)
              Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _aspectRatio,
                      child: Video(controller: controller),
                    ),
                  ),
                  _buildControlsOverlay(),
                ],
              )
            else
              _buildLoadingLayer(),
            if (_isLongPressing)
              const Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: _LongPressSpeedBadge(),
                ),
              ),
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

  Widget _buildControlsOverlay() {
    final shouldShowControls =
        _showControls || !_isPlaying || _isCompleted();
    final player = _player;
    if (player == null) {
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
                    icon: Icon(_resolvePrimaryActionIcon()),
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
                    _buildProgressBar(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _formatDuration(_displayPosition()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        if (_isBuffering)
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
                        _buildSpeedButton(),
                        Text(
                          _formatDuration(_effectiveDuration()),
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

  /// 自建进度条：支持点击跳转与拖拽
  Widget _buildProgressBar() {
    final duration = _effectiveDuration();
    final position = _displayPosition();
    final progress = duration.inMicroseconds > 0
        ? (position.inMicroseconds / duration.inMicroseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _onProgressBarDragStart();
            final ratio =
                (details.localPosition.dx / totalWidth).clamp(0.0, 1.0);
            unawaited(_seekToClamped(
              Duration(
                milliseconds: (duration.inMilliseconds * ratio).round(),
              ),
            ));
          },
          onHorizontalDragStart: (_) => _onProgressBarDragStart(),
          onHorizontalDragUpdate: (details) {
            final ratio =
                (details.localPosition.dx / totalWidth).clamp(0.0, 1.0);
            _onProgressBarDragUpdate(ratio);
          },
          onHorizontalDragEnd: (_) => unawaited(_onProgressBarDragEnd()),
          child: SizedBox(
            height: 28,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  // 背景轨道
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 已播放部分
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // 拖拽手柄
                  Positioned(
                    left: (progress * totalWidth).clamp(
                      0.0,
                      (totalWidth - 6).clamp(0.0, double.infinity),
                    ),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  IconData _resolvePrimaryActionIcon() {
    if (_isCompleted()) {
      return Icons.replay_rounded;
    }
    return _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
  }

  bool get _isPlaying => _player?.state.playing ?? false;

  bool get _isBuffering => _player?.state.buffering ?? false;

  bool _isCompleted() {
    final player = _player;
    if (player == null) return false;
    if (player.state.completed) return true;
    final duration = _effectiveDuration();
    if (duration.inMicroseconds <= 0) return false;
    return _safePosition().compareTo(duration - _completionTolerance) >= 0;
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

  /// 拖拽时显示暂存位置，否则显示实际播放位置
  Duration _displayPosition() {
    return _scrubPosition ?? _safePosition();
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

/// 长按倍速时显示的提示徽章
class _LongPressSpeedBadge extends StatelessWidget {
  const _LongPressSpeedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
          SizedBox(width: 4),
          Text(
            '2.0x 倍速播放中',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
