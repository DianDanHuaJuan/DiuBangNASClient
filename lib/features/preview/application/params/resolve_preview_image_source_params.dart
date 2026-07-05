/// 文件输入：NasPath、PreviewItemEntity、网格缩略图字节
/// 文件职责：封装图片来源解析动作的输入参数
/// 文件对外接口：ResolvePreviewImageSourceParams
/// 文件包含：ResolvePreviewImageSourceParams
import 'dart:typed_data';

import '../../../../core/path/nas_path.dart';
import '../../domain/entities/preview_item_entity.dart';

/// 输入：NasPath、PreviewItemEntity、网格缩略图字节。
/// 职责：描述预览图片来源解析所需的完整输入。
/// 对外接口：ResolvePreviewImageSourceParams 数据对象。
class ResolvePreviewImageSourceParams {
  final NasPath nasPath;
  final PreviewItemEntity item;
  final Uint8List? thumbnailData;

  const ResolvePreviewImageSourceParams({
    required this.nasPath,
    required this.item,
    required this.thumbnailData,
  });
}
