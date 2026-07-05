/// 文件输入：远程路径、本地路径、根目录 ID
/// 文件职责：封装下载任务参数
/// 文件对外接口：EnqueueDownloadParams
/// 文件包含：EnqueueDownloadParams
class EnqueueDownloadParams {
  final String remotePath;
  final String localPath;
  final String? rootId;

  const EnqueueDownloadParams({
    required this.remotePath,
    required this.localPath,
    this.rootId,
  });
}
