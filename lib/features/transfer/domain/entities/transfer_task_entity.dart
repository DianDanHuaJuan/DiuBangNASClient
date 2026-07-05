/// 文件输入：传输任务 ID、文件路径、大小、方向、状态、进度
/// 文件职责：表达传输任务实体
/// 文件对外接口：TransferTaskEntity
/// 文件包含：TransferTaskEntity
import 'transfer_direction.dart';
import 'transfer_status.dart';

class TransferTaskEntity {
  final String id;
  final String rootId;
  final String localPath;
  final String remotePath;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final TransferDirection direction;
  final TransferStatus status;
  final DateTime createdAt;
  final String? errorMessage;

  const TransferTaskEntity({
    required this.id,
    required this.rootId,
    required this.localPath,
    required this.remotePath,
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.errorMessage,
  });

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0;

  String get formattedSize {
    if (totalBytes < 1024) {
      return '$totalBytes B';
    }
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedTransferred {
    final bytes = transferredBytes;
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

  TransferTaskEntity copyWith({
    String? id,
    String? rootId,
    String? localPath,
    String? remotePath,
    String? fileName,
    int? totalBytes,
    int? transferredBytes,
    TransferDirection? direction,
    TransferStatus? status,
    DateTime? createdAt,
    String? errorMessage,
  }) {
    return TransferTaskEntity(
      id: id ?? this.id,
      rootId: rootId ?? this.rootId,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
