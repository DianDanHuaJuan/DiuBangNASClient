/// 文件输入：预览信息、URL、headers、策略
/// 文件职责：表达预览项实体
/// 文件对外接口：PreviewItemEntity
/// 文件包含：PreviewItemEntity
import 'preview_kind.dart';
import 'preview_strategy.dart';

class PreviewItemEntity {
  final PreviewKind kind;
  final PreviewStrategy strategy;
  final String? url;
  final Map<String, String>? headers;
  final String? contentType;
  final int? size;
  final String? thumbnailUrl;
  final String? posterUrl;
  final String? expiresAt;

  const PreviewItemEntity({
    required this.kind,
    required this.strategy,
    this.url,
    this.headers,
    this.contentType,
    this.size,
    this.thumbnailUrl,
    this.posterUrl,
    this.expiresAt,
  });

  String get formattedSize {
    if (size == null) {
      return '';
    }

    final bytes = size!;
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get isImage => kind == PreviewKind.image;
  bool get isVideo => kind == PreviewKind.video;
  bool get isAudio => kind == PreviewKind.audio;
  bool get isDocument => kind == PreviewKind.document;
  bool get isSupported => kind != PreviewKind.unknown;
}
