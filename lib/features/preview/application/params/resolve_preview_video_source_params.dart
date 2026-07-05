/// 文件输入：NasPath、PreviewItemEntity、网格缩略图字节
/// 文件职责：封装视频来源解析动作的输入参数
/// 文件对外接口：ResolvePreviewVideoSourceParams
/// 文件包含：ResolvePreviewVideoSourceParams
import 'dart:typed_data';

import '../../../../core/path/nas_path.dart';
import '../../domain/entities/preview_item_entity.dart';

/// 输入：NasPath、PreviewItemEntity、网格缩略图字节。
/// 职责：为视频来源解析动作聚合业务路径、预览元信息与现有缩略图上下文。
/// 对外接口：ResolvePreviewVideoSourceParams 值对象。
class ResolvePreviewVideoSourceParams {
  final NasPath nasPath;
  final PreviewItemEntity item;
  final Uint8List? thumbnailData;

  const ResolvePreviewVideoSourceParams({
    required this.nasPath,
    required this.item,
    required this.thumbnailData,
  });
}
