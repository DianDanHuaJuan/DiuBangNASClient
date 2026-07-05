/// 文件输入：批量缩略图响应 JSON
/// 文件职责：解析批量缩略图响应，匹配 multipart 响应格式
/// 文件对外接口：BatchThumbnailResponseDto、ThumbnailResultDto
/// 文件包含：BatchThumbnailResponseDto、ThumbnailResultDto
class ThumbnailResultDto {
  final String path;
  final int index;
  final bool success;
  final String? contentType;
  final int? size;
  final String? error;

  const ThumbnailResultDto({
    required this.path,
    required this.index,
    required this.success,
    this.contentType,
    this.size,
    this.error,
  });

  factory ThumbnailResultDto.fromJson(Map<String, dynamic> json) {
    return ThumbnailResultDto(
      path: json['path'] as String,
      index: json['index'] as int,
      success: json['success'] as bool,
      contentType: json['contentType'] as String?,
      size: json['size'] as int?,
      error: json['error'] as String?,
    );
  }
}

class BatchThumbnailResponseDto {
  final List<ThumbnailResultDto> thumbnails;
  final int total;
  final int successCount;
  final int failedCount;

  const BatchThumbnailResponseDto({
    required this.thumbnails,
    required this.total,
    required this.successCount,
    required this.failedCount,
  });

  factory BatchThumbnailResponseDto.fromJson(Map<String, dynamic> json) {
    final thumbnailsList = json['thumbnails'] as List<dynamic>;
    return BatchThumbnailResponseDto(
      thumbnails: thumbnailsList
          .map((e) => ThumbnailResultDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      successCount: json['successCount'] as int,
      failedCount: json['failedCount'] as int,
    );
  }
}
