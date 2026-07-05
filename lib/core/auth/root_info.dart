/// 文件输入：根目录 JSON 数据
/// 文件职责：表达存储根目录信息，支持多根目录切换
/// 文件对外接口：RootInfo
/// 文件包含：RootInfo
class RootInfo {
  final String id;
  final String name;
  final String path;
  final String type;
  final String? mediaType;
  final bool writable;

  const RootInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    this.mediaType,
    required this.writable,
  });

  factory RootInfo.fromJson(Map<String, dynamic> json) {
    return RootInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      type: json['type'] as String,
      mediaType: json['mediaType'] as String?,
      writable: json['writable'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'type': type,
      'mediaType': mediaType,
      'writable': writable,
    };
  }

  bool get isLocal => type == 'local';
  bool get isMediastore => type == 'mediastore';
  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
}
