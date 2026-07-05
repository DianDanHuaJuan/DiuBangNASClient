/// 文件输入：本地资源标识、路径、大小、来源描述
/// 文件职责：统一表达立即备份待上传的本地资源，屏蔽图库与文件系统来源差异
/// 文件对外接口：BackupSourceItem
/// 文件包含：BackupSourceItem
import 'backup_source_type.dart';

class BackupSourceItem {
  final String id;
  final BackupSourceType sourceType;
  final String localPath;
  final String displayName;
  final int size;
  final String? mimeType;
  final String? sourceLabel;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final int? durationSeconds;

  const BackupSourceItem({
    required this.id,
    required this.sourceType,
    required this.localPath,
    required this.displayName,
    required this.size,
    this.mimeType,
    this.sourceLabel,
    this.createdAt,
    this.modifiedAt,
    this.durationSeconds,
  });
}
