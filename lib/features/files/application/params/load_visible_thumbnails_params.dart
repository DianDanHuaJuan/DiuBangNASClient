/// 文件输入：路径列表、缩略图类型
/// 文件职责：封装可见区域缩略图加载参数
/// 文件对外接口：LoadVisibleThumbnailsParams
/// 文件包含：LoadVisibleThumbnailsParams
class LoadVisibleThumbnailsParams {
  final List<String> paths;
  final String type;

  const LoadVisibleThumbnailsParams({required this.paths, this.type = 'grid'});
}
