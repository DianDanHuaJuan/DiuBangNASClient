/// 文件输入：存储信息 JSON
/// 文件职责：解析存储信息 DTO
/// 文件对外接口：StorageInfoDto
/// 文件包含：StorageInfoDto
class StorageInfoDto {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final double usagePercent;

  const StorageInfoDto({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.usagePercent,
  });

  factory StorageInfoDto.fromJson(Map<String, dynamic> json) {
    return StorageInfoDto(
      totalBytes: json['totalBytes'] as int? ?? 0,
      usedBytes: json['usedBytes'] as int? ?? 0,
      freeBytes: json['freeBytes'] as int? ?? 0,
      usagePercent: (json['usagePercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
