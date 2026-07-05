/// 文件输入：文件条目 JSON
/// 文件职责：解析文件条目 DTO
/// 文件对外接口：FileEntryDto
/// 文件包含：FileEntryDto
class FileEntryDto {
  final String name;
  final String path;
  final String type;
  final int size;
  final String? modifiedAt;

  const FileEntryDto({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    this.modifiedAt,
  });

  factory FileEntryDto.fromJson(Map<String, dynamic> json) {
    return FileEntryDto(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      type: json['type'] as String? ?? 'file',
      size: json['size'] as int? ?? 0,
      modifiedAt: json['modifiedAt'] as String?,
    );
  }
}
