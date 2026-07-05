/// 文件输入：上传回调、上传状态、底部间距
/// 文件职责：为文件浏览页提供可展开上传悬浮球和上传中的进度条
/// 文件对外接口：FileBrowserFloatingActionsWidget
/// 文件包含：FileBrowserFloatingActionsWidget、_UploadBubble、_UploadProgressPill
import 'package:flutter/material.dart';

/// 输入：上传回调、上传状态、底部间距。
/// 职责：在文件浏览页中渲染可拖动、可展开的上传悬浮球，上传中切换为进度条。
/// 对外接口：FileBrowserFloatingActionsWidget widget。
class FileBrowserFloatingActionsWidget extends StatefulWidget {
  final VoidCallback onUploadMediaTap;
  final VoidCallback onUploadFilesTap;
  final double bottomPadding;
  final bool showUploadAction;
  final bool isUploading;
  final String? uploadFileName;
  final double uploadProgress;

  const FileBrowserFloatingActionsWidget({
    super.key,
    required this.onUploadMediaTap,
    required this.onUploadFilesTap,
    required this.bottomPadding,
    required this.showUploadAction,
    required this.isUploading,
    this.uploadFileName,
    this.uploadProgress = 0,
  });

  @override
  State<FileBrowserFloatingActionsWidget> createState() =>
      _FileBrowserFloatingActionsWidgetState();
}

class _FileBrowserFloatingActionsWidgetState
    extends State<FileBrowserFloatingActionsWidget> {
  static const double _uploadBubbleSize = 68;
  static const double _optionBubbleSize = 56;
  static const double _screenMargin = 24;
  static const double _optionSpacing = 12;

  Offset? _uploadOffset;
  bool _menuExpanded = false;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (widget.isUploading && widget.uploadFileName != null) {
            return Stack(
              children: [
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: _progressBottom(mediaQuery.padding),
                  child: _UploadProgressPill(
                    fileName: widget.uploadFileName!,
                    progress: widget.uploadProgress,
                  ),
                ),
              ],
            );
          }

          if (!widget.showUploadAction) {
            return const SizedBox.shrink();
          }

          final uploadOffset = _resolveUploadOffset(
            constraints: constraints,
            padding: mediaQuery.padding,
          );
          _uploadOffset ??= uploadOffset;

          final expandToLeft = _expandToLeft(constraints, uploadOffset);
          final clusterLeft = _clusterLeft(uploadOffset, expandToLeft: expandToLeft);

          return Stack(
            children: [
              if (_menuExpanded)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _collapseMenu,
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
              Positioned(
                left: clusterLeft,
                top: uploadOffset.dy,
                child: GestureDetector(
                  onPanStart: (_) {
                    if (_menuExpanded) {
                      _collapseMenu();
                    }
                  },
                  onPanUpdate: (details) {
                    final currentOffset = _uploadOffset ?? uploadOffset;
                    setState(() {
                      final proposed = Offset(
                        currentOffset.dx + details.delta.dx,
                        currentOffset.dy + details.delta.dy,
                      );
                      _uploadOffset = _clampOffset(
                        offset: proposed,
                        constraints: constraints,
                        padding: mediaQuery.padding,
                      );
                    });
                  },
                  child: _buildFabAnchor(expandToLeft: expandToLeft),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFabAnchor({required bool expandToLeft}) {
    final clusterWidth = _menuExpanded
        ? _expandedClusterWidth()
        : _uploadBubbleSize;
    final clusterHeight = _menuExpanded ? 80.0 : _uploadBubbleSize;

    return SizedBox(
      width: clusterWidth,
      height: clusterHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_menuExpanded)
            Positioned(
              top: 0,
              right: expandToLeft ? _uploadBubbleSize + _optionSpacing : null,
              left: expandToLeft ? null : _uploadBubbleSize + _optionSpacing,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _buildOptionWidgets(expandToLeft: expandToLeft),
              ),
            ),
          Positioned(
            top: 0,
            right: expandToLeft ? 0 : null,
            left: expandToLeft ? null : 0,
            child: _UploadBubble(
              expanded: _menuExpanded,
              onTap: () {
                setState(() {
                  _menuExpanded = !_menuExpanded;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  double _expandedClusterWidth() {
    return _uploadBubbleSize +
        _optionSpacing +
        (_optionBubbleSize * 2) +
        _optionSpacing;
  }

  List<Widget> _buildOptionWidgets({required bool expandToLeft}) {
    final mediaOption = _UploadOptionBubble(
      label: '图片/视频',
      icon: Icons.photo_library_outlined,
      onTap: () {
        _collapseMenu();
        widget.onUploadMediaTap();
      },
    );
    final fileOption = _UploadOptionBubble(
      label: '文件',
      icon: Icons.insert_drive_file_rounded,
      onTap: () {
        _collapseMenu();
        widget.onUploadFilesTap();
      },
    );

    final options = expandToLeft
        ? <Widget>[fileOption, mediaOption]
        : <Widget>[mediaOption, fileOption];

    return [
      for (var index = 0; index < options.length; index++)
        Padding(
          padding: EdgeInsets.only(
            right: index < options.length - 1 ? _optionSpacing : 0,
          ),
          child: AnimatedSlide(
            offset: _menuExpanded ? Offset.zero : Offset(expandToLeft ? 0.2 : -0.2, 0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _menuExpanded ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_menuExpanded,
                child: options[index],
              ),
            ),
          ),
        ),
    ];
  }

  double _clusterLeft(Offset uploadOffset, {required bool expandToLeft}) {
    if (!_menuExpanded || !expandToLeft) {
      return uploadOffset.dx;
    }

    final shift = _expandedClusterWidth() - _uploadBubbleSize;
    final left = uploadOffset.dx - shift;
    return left < _screenMargin ? _screenMargin : left;
  }

  bool _expandToLeft(BoxConstraints constraints, Offset uploadOffset) {
    return uploadOffset.dx > constraints.maxWidth / 2;
  }

  void _collapseMenu() {
    if (!_menuExpanded) {
      return;
    }
    setState(() {
      _menuExpanded = false;
    });
  }

  Offset _resolveUploadOffset({
    required BoxConstraints constraints,
    required EdgeInsets padding,
  }) {
    final maxLeft = _maxLeft(constraints);
    final minTop = _minTop(padding);
    final maxTop = _maxTop(constraints, padding);
    final currentOffset = _uploadOffset ?? Offset(maxLeft, maxTop);
    return Offset(
      currentOffset.dx.clamp(_screenMargin, maxLeft).toDouble(),
      currentOffset.dy.clamp(minTop, maxTop).toDouble(),
    );
  }

  Offset _clampOffset({
    required Offset offset,
    required BoxConstraints constraints,
    required EdgeInsets padding,
  }) {
    final maxLeft = _maxLeft(constraints);
    final minTop = _minTop(padding);
    final maxTop = _maxTop(constraints, padding);
    return Offset(
      offset.dx.clamp(_screenMargin, maxLeft).toDouble(),
      offset.dy.clamp(minTop, maxTop).toDouble(),
    );
  }

  double _maxLeft(BoxConstraints constraints) {
    final value = constraints.maxWidth - _uploadBubbleSize - _screenMargin;
    if (value < _screenMargin) {
      return _screenMargin;
    }
    return value;
  }

  double _minTop(EdgeInsets padding) {
    return padding.top + _screenMargin;
  }

  double _maxTop(BoxConstraints constraints, EdgeInsets padding) {
    final value =
        constraints.maxHeight -
        padding.bottom -
        _uploadBubbleSize -
        _screenMargin;
    final minTop = _minTop(padding);
    if (value < minTop) {
      return minTop;
    }
    return value;
  }

  double _progressBottom(EdgeInsets padding) {
    final offset = widget.bottomPadding - 40;
    final clamped = offset < 24 ? 24.0 : offset;
    return padding.bottom + clamped;
  }
}

/// 输入：展开状态、点击回调。
/// 职责：渲染主上传悬浮球，展开时显示关闭图标。
/// 对外接口：_UploadBubble widget。
class _UploadBubble extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _UploadBubble({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 4,
      shadowColor: const Color(0xFF000000).withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).primaryColor,
          ),
          child: Center(
            child: Icon(
              expanded ? Icons.close_rounded : Icons.arrow_upward_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}

/// 输入：标签、图标、点击回调。
/// 职责：渲染展开菜单中的子上传选项。
/// 对外接口：_UploadOptionBubble widget。
class _UploadOptionBubble extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _UploadOptionBubble({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          elevation: 3,
          shadowColor: const Color(0xFF000000).withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF2E3C34),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 输入：文件名、上传进度。
/// 职责：渲染上传中的条形圆角进度框。
/// 对外接口：_UploadProgressPill widget。
class _UploadProgressPill extends StatelessWidget {
  final String fileName;
  final double progress;

  const _UploadProgressPill({required this.fileName, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedProgress = progress.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: clampedProgress,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.centerLeft,
            child: Text(
              '正在上传 $fileName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF2E3C34),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
