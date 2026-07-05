/// 文件输入：缩略图路径、二进制数据、内容类型
/// 文件职责：表达单个缩略图实体
/// 文件对外接口：ThumbnailItemEntity
/// 文件包含：ThumbnailItemEntity
import 'dart:typed_data';

class ThumbnailItemEntity {
  final String path;
  final Uint8List data;
  final String contentType;
  final int size;

  const ThumbnailItemEntity({
    required this.path,
    required this.data,
    required this.contentType,
    required this.size,
  });
}
