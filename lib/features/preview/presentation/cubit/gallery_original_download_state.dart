/// 文件输入：原图下载任务信息、保存状态、错误信息
/// 文件职责：表达 Gallery 页面单项原图动作的渲染状态
/// 文件对外接口：GalleryOriginalDownloadState
/// 文件包含：GalleryOriginalDownloadState

/// 输入：原图下载任务信息、保存状态、错误信息。
/// 职责：统一描述图片原图下载、保存和查看动作的页面状态。
/// 对外接口：GalleryOriginalDownloadState 值对象及其状态 getter。
class GalleryOriginalDownloadState {
  static const Object _sentinel = Object();

  static const GalleryOriginalDownloadState idle =
      GalleryOriginalDownloadState();

  final String? taskId;
  final String? localPath;
  final String? publicUri;
  final double progress;
  final bool isDownloading;
  final bool isSaving;
  final String? errorMessage;

  const GalleryOriginalDownloadState({
    this.taskId,
    this.localPath,
    this.publicUri,
    this.progress = 0,
    this.isDownloading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  bool get hasLocalPath => localPath != null && localPath!.trim().isNotEmpty;

  bool get hasPublicUri => publicUri != null && publicUri!.trim().isNotEmpty;

  bool get isOriginalReady =>
      hasLocalPath && !isDownloading && !isSaving && !hasFailure;

  bool get canViewOriginal => isOriginalReady;

  bool get isCached => isOriginalReady;

  bool get isSaved => hasPublicUri;

  bool get canSaveToPublic => isOriginalReady && !hasPublicUri && !isSaving;

  bool get hasFailure =>
      errorMessage != null && errorMessage!.trim().isNotEmpty;

  bool get needsSaveRetry => hasFailure && isOriginalReady && !isSaved;

  bool get needsDownloadRetry => hasFailure && !isOriginalReady;

  GalleryOriginalDownloadState copyWith({
    Object? taskId = _sentinel,
    Object? localPath = _sentinel,
    Object? publicUri = _sentinel,
    double? progress,
    bool? isDownloading,
    bool? isSaving,
    Object? errorMessage = _sentinel,
  }) {
    return GalleryOriginalDownloadState(
      taskId: identical(taskId, _sentinel) ? this.taskId : taskId as String?,
      localPath: identical(localPath, _sentinel)
          ? this.localPath
          : localPath as String?,
      publicUri: identical(publicUri, _sentinel)
          ? this.publicUri
          : publicUri as String?,
      progress: progress ?? this.progress,
      isDownloading: isDownloading ?? this.isDownloading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}
