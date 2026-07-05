/// 文件输入：预览 JSON 响应
/// 文件职责：解析预览 DTO，匹配 /api/v1/preview/meta 响应格式
/// 文件对外接口：PreviewItemDto
/// 文件包含：PreviewItemDto
import '../../domain/entities/preview_kind.dart';
import '../../domain/entities/preview_strategy.dart';

class PreviewItemDto {
  final String? kind;
  final String strategy;
  final String? url;
  final Map<String, String>? headers;
  final String? contentType;
  final int? size;
  final String? thumbnailUrl;
  final String? posterUrl;
  final String? expiresAt;

  const PreviewItemDto({
    this.kind,
    required this.strategy,
    this.url,
    this.headers,
    this.contentType,
    this.size,
    this.thumbnailUrl,
    this.posterUrl,
    this.expiresAt,
  });

  factory PreviewItemDto.fromJson(Map<String, dynamic> json) {
    Map<String, String>? headers;
    final headersJson = json['headers'];
    if (headersJson is Map) {
      headers = headersJson.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    return PreviewItemDto(
      kind: json['kind'] as String?,
      strategy: json['strategy'] as String? ?? 'unsupported',
      url: json['url'] as String?,
      headers: headers,
      contentType: json['contentType'] as String?,
      size: json['size'] as int?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      posterUrl: json['posterUrl'] as String?,
      expiresAt: json['expiresAt'] as String?,
    );
  }

  PreviewKind get kindEnum {
    switch (kind) {
      case 'image':
        return PreviewKind.image;
      case 'video':
        return PreviewKind.video;
      case 'audio':
        return PreviewKind.audio;
      case 'document':
        return PreviewKind.document;
      default:
        return PreviewKind.unknown;
    }
  }

  PreviewStrategy get strategyEnum {
    switch (strategy) {
      case 'direct':
        return PreviewStrategy.native;
      case 'progressive':
        return PreviewStrategy.progressive;
      case 'hls':
      case 'transcode':
        return PreviewStrategy.streaming;
      default:
        return PreviewStrategy.unsupported;
    }
  }

  bool get isSupported =>
      kind != null && strategyEnum != PreviewStrategy.unsupported;
}
