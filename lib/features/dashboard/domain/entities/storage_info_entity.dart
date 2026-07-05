/// 文件输入：总容量、已用容量、可用容量
/// 文件职责：表达存储信息实体
/// 文件对外接口：StorageInfoEntity
/// 文件包含：StorageInfoEntity
class StorageInfoEntity {
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;

  const StorageInfoEntity({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
  });

  double get usagePercentage => totalBytes > 0 ? usedBytes / totalBytes : 0;

  String get formattedTotal => _formatBytes(totalBytes);
  String get formattedUsed => _formatBytes(usedBytes);
  String get formattedAvailable => _formatBytes(availableBytes);

  String _formatBytes(int bytes) {
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
}
