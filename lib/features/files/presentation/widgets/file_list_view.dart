import 'dart:async';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/file_entry_entity.dart';
import 'selection_badge.dart';

class FileListView extends StatelessWidget {
  const FileListView({
    super.key,
    required this.files,
    required this.getThumbnail,
    required this.watchThumbnail,
    required this.getHeroTag,
    required this.onTap,
    this.onLongPressNonPreview,
    this.selectionMode = false,
    this.selectedPaths,
    this.onSelectToggle,
    this.onLongSelect,
    this.bottomPadding = 100,
    this.enableHero = true,
  });

  final List<FileEntryEntity> files;
  final Uint8List? Function(String filePath) getThumbnail;
  final Stream<void> Function(String filePath) watchThumbnail;
  final String Function(FileEntryEntity file) getHeroTag;
  final void Function(FileEntryEntity file) onTap;
  final void Function(FileEntryEntity file)? onLongPressNonPreview;
  final bool selectionMode;
  final Set<String>? selectedPaths;
  final void Function(String filePath)? onSelectToggle;
  final void Function(String filePath)? onLongSelect;
  final double bottomPadding;
  final bool enableHero;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: Text('当前目录为空', style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      );
    }

    final usesFileNameLabels = files.any(
      (file) => file.isFile && !file.isImage && !file.isVideo,
    );

    return SliverPadding(
      padding: EdgeInsets.only(left: 24, right: 24, bottom: bottomPadding),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final file = files[index];

            return MetaData(
              key: ValueKey<String>(file.path),
              metaData: file.path,
              child: ThumbnailGridTile(
                file: file,
                getThumbnail: getThumbnail,
                watchThumbnail: watchThumbnail,
                heroTag: getHeroTag(file),
                enableHero: enableHero,
                selected:
                    selectionMode &&
                    (selectedPaths?.contains(file.path) ?? false),
                selectionMode: selectionMode,
                onSelectToggle: onSelectToggle != null
                    ? () => onSelectToggle!(file.path)
                    : null,
                onLongSelect: onLongSelect != null
                    ? () => onLongSelect!(file.path)
                    : null,
                onTap: () => onTap(file),
                onLongPressNonPreview: onLongPressNonPreview != null
                    ? () => onLongPressNonPreview!(file)
                    : null,
              ),
            );
          },
          childCount: files.length,
          findChildIndexCallback: (Key key) {
            if (key is ValueKey<String>) {
              final index = files.indexWhere((f) => f.path == key.value);
              if (index != -1) {
                return index;
              }
            }
            return null;
          },
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: usesFileNameLabels ? 0.78 : 1,
        ),
      ),
    );
  }
}

class ThumbnailGridTile extends StatelessWidget {
  const ThumbnailGridTile({
    super.key,
    required this.file,
    required this.getThumbnail,
    required this.watchThumbnail,
    required this.heroTag,
    required this.onTap,
    this.onLongPressNonPreview,
    this.selected = false,
    this.selectionMode = false,
    this.onSelectToggle,
    this.onLongSelect,
    this.enableHero = true,
  });

  final FileEntryEntity file;
  final Uint8List? Function(String filePath) getThumbnail;
  final Stream<void> Function(String filePath) watchThumbnail;
  final String heroTag;
  final VoidCallback onTap;
  final VoidCallback? onLongPressNonPreview;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onLongSelect;
  final bool enableHero;

  Color _iconBackground() {
    if (file.isDirectory) {
      return const Color(0xFFEAF4EC);
    }

    switch (file.extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return const Color(0xFFF1EFE7);
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case '3gp':
        return const Color(0xFFE9EEF7);
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'xls':
      case 'xlsx':
        return const Color(0xFFF4ECE7);
      default:
        return const Color(0xFFF2F1EE);
    }
  }

  Color _iconColor() {
    if (file.isDirectory) {
      return const Color(0xFF3D8A5A);
    }

    switch (file.extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return const Color(0xFF9B7A48);
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case '3gp':
        return const Color(0xFF5777A8);
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'xls':
      case 'xlsx':
        return const Color(0xFFB5664C);
      default:
        return const Color(0xFF7C7974);
    }
  }

  IconData _getFileIcon() {
    if (file.isDirectory) {
      return Icons.folder;
    }

    switch (file.extension.toLowerCase()) {
      // 图片
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      // 视频
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case '3gp':
        return Icons.videocam;
      // 音频
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return Icons.audio_file;
      // PDF
      case 'pdf':
        return Icons.picture_as_pdf;
      // Word
      case 'doc':
      case 'docx':
        return Icons.article;
      // Excel / CSV
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.grid_on;
      // PowerPoint
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      // 压缩包
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      // 文本
      case 'txt':
      case 'md':
      case 'log':
        return Icons.text_snippet;
      // 代码
      case 'dart':
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
      case 'py':
      case 'java':
      case 'kt':
      case 'swift':
      case 'c':
      case 'cpp':
      case 'h':
      case 'go':
      case 'rs':
      case 'rb':
      case 'php':
      case 'html':
      case 'css':
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'sh':
        return Icons.code;
      // 可执行文件
      case 'apk':
        return Icons.android;
      case 'exe':
      case 'msi':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder<void>(
        stream: watchThumbnail(file.path),
        builder: (context, snapshot) {
          final thumbnailData = getThumbnail(file.path);
          final hasThumbnail =
              thumbnailData != null && (file.isImage || file.isVideo);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: selectionMode && onSelectToggle != null
                ? onSelectToggle
                : onTap,
            onLongPressStart: (details) {
              final isPreviewableMedia = file.isImage || file.isVideo;
              if (isPreviewableMedia && onLongSelect != null) {
                onLongSelect!();
                return;
              }
              if (file.isFile &&
                  !file.isImage &&
                  !file.isVideo &&
                  onLongPressNonPreview != null) {
                onLongPressNonPreview!();
                return;
              }
              onLongSelect?.call();
            },
            child: SelectionBadge(
              selected: selected,
              child: ColoredBox(
                color: Colors.white,
                child: hasThumbnail
                    ? _buildThumbnailImage(thumbnailData)
                    : _buildNonThumbnailTile(
                        showFileName: !file.isImage && !file.isVideo,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThumbnailImage(Uint8List thumbnailData) {
    final image = ExtendedImage.memory(
      thumbnailData,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      enableLoadState: false,
      filterQuality: FilterQuality.low,
      loadStateChanged: (state) {
        if (state.extendedImageLoadState == LoadState.failed) {
          return _buildNonThumbnailTile(showFileName: false);
        }
        return null;
      },
    );

    if (!enableHero) {
      return image;
    }

    return Hero(tag: heroTag, child: image);
  }

  Widget _buildNonThumbnailTile({required bool showFileName}) {
    if (!showFileName) {
      return _buildIconPlaceholder();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: _iconBackground(),
            alignment: Alignment.center,
            child: Icon(_getFileIcon(), size: 28, color: _iconColor()),
          ),
        ),
        SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: Color(0xFF4B5563),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconPlaceholder() {
    return Container(
      color: _iconBackground(),
      child: Center(child: Icon(_getFileIcon(), size: 32, color: _iconColor())),
    );
  }
}
