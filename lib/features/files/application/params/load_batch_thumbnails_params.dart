/// 文件输入：路径列表、缩略图类型
/// 文件职责：封装批量加载缩略图参数
/// 文件对外接口：LoadBatchThumbnailsParams
/// 文件包含：LoadBatchThumbnailsParams
class LoadBatchThumbnailsParams {
  final List<String> paths;
  final String type;

  const LoadBatchThumbnailsParams({required this.paths, this.type = 'grid'});
}
