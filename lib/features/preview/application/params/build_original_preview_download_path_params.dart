/// 文件输入：rootId、远端原图路径
/// 文件职责：封装原图下载临时路径构建所需参数
/// 文件对外接口：BuildOriginalPreviewDownloadPathParams
/// 文件包含：BuildOriginalPreviewDownloadPathParams

/// 输入：rootId、远端原图路径。
/// 职责：统一描述原图下载到本地缓存时需要的路径参数。
/// 对外接口：BuildOriginalPreviewDownloadPathParams 值对象。
class BuildOriginalPreviewDownloadPathParams {
  final String rootId;
  final String remotePath;

  const BuildOriginalPreviewDownloadPathParams({
    required this.rootId,
    required this.remotePath,
  });
}
