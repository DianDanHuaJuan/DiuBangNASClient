/// 文件输入：媒体文件列表、预览项缓存、缩略图数据
/// 文件职责：表达 Gallery 页面状态
/// 文件对外接口：GalleryState
/// 文件包含：GalleryState
import 'dart:typed_data';

import '../../../files/domain/entities/file_entry_entity.dart';
import '../../domain/entities/preview_image_source.dart';
import '../../domain/entities/preview_item_entity.dart';
import '../../domain/entities/preview_video_source.dart';
import 'gallery_original_download_state.dart';

class GalleryState {
  final List<FileEntryEntity> mediaFiles;
  final String rootId;
  final int currentIndex;
  final Map<int, PreviewItemEntity> previewItems;
  final Map<int, PreviewImageSource> imageSources;
  final Map<int, PreviewVideoSource> videoSources;
  final Map<int, bool> loadingStates;
  final Map<String, Uint8List> thumbnails;
  final Map<int, GalleryOriginalDownloadState> originalStates;

  const GalleryState({
    required this.mediaFiles,
    required this.rootId,
    required this.currentIndex,
    required this.previewItems,
    required this.imageSources,
    required this.videoSources,
    required this.loadingStates,
    required this.thumbnails,
    required this.originalStates,
  });

  factory GalleryState.initial({
    required List<FileEntryEntity> mediaFiles,
    required String rootId,
    required int initialIndex,
    required Map<String, Uint8List> thumbnails,
  }) {
    return GalleryState(
      mediaFiles: mediaFiles,
      rootId: rootId,
      currentIndex: initialIndex,
      previewItems: {},
      imageSources: {},
      videoSources: {},
      loadingStates: {},
      thumbnails: thumbnails,
      originalStates: {},
    );
  }

  bool isLoading(int index) => loadingStates[index] ?? false;

  PreviewItemEntity? getPreviewItem(int index) => previewItems[index];

  PreviewImageSource? getImageSource(int index) => imageSources[index];

  PreviewVideoSource? getVideoSource(int index) => videoSources[index];

  Uint8List? getThumbnail(String filePath) => thumbnails[filePath];

  GalleryOriginalDownloadState getOriginalState(int index) {
    return originalStates[index] ?? GalleryOriginalDownloadState.idle;
  }

  int get length => mediaFiles.length;

  FileEntryEntity getFile(int index) => mediaFiles[index];

  bool hasPreviewItem(int index) => previewItems.containsKey(index);

  GalleryState copyWith({
    List<FileEntryEntity>? mediaFiles,
    String? rootId,
    int? currentIndex,
    Map<int, PreviewItemEntity>? previewItems,
    Map<int, PreviewImageSource>? imageSources,
    Map<int, PreviewVideoSource>? videoSources,
    Map<int, bool>? loadingStates,
    Map<String, Uint8List>? thumbnails,
    Map<int, GalleryOriginalDownloadState>? originalStates,
  }) {
    return GalleryState(
      mediaFiles: mediaFiles ?? this.mediaFiles,
      rootId: rootId ?? this.rootId,
      currentIndex: currentIndex ?? this.currentIndex,
      previewItems: previewItems ?? this.previewItems,
      imageSources: imageSources ?? this.imageSources,
      videoSources: videoSources ?? this.videoSources,
      loadingStates: loadingStates ?? this.loadingStates,
      thumbnails: thumbnails ?? this.thumbnails,
      originalStates: originalStates ?? this.originalStates,
    );
  }
}
