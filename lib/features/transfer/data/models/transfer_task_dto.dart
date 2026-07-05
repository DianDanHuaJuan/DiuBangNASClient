/// 文件输入：传输任务 JSON
/// 文件职责：解析传输任务 DTO
/// 文件对外接口：TransferTaskDto
/// 文件包含：TransferTaskDto
import '../../domain/entities/transfer_direction.dart';
import '../../domain/entities/transfer_status.dart';

class TransferTaskDto {
  final String id;
  final String rootId;
  final String localPath;
  final String remotePath;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final String direction;
  final String status;
  final String createdAt;
  final String? errorMessage;

  const TransferTaskDto({
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

  factory TransferTaskDto.fromJson(Map<String, dynamic> json) {
    return TransferTaskDto(
      id: json['id'] as String? ?? '',
      rootId: json['rootId'] as String? ?? 'fs',
      localPath: json['localPath'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      totalBytes: json['totalBytes'] as int? ?? 0,
      transferredBytes: json['transferredBytes'] as int? ?? 0,
      direction: json['direction'] as String? ?? 'download',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['createdAt'] as String? ?? '',
      errorMessage: json['errorMessage'] as String?,
    );
  }

  TransferDirection get directionEnum {
    return direction == 'upload'
        ? TransferDirection.upload
        : TransferDirection.download;
  }

  TransferStatus get statusEnum {
    switch (status) {
      case 'pending':
        return TransferStatus.pending;
      case 'paused':
        return TransferStatus.paused;
      case 'transferring':
        return TransferStatus.transferring;
      case 'awaitingConflictResolution':
        return TransferStatus.awaitingConflictResolution;
      case 'completed':
        return TransferStatus.completed;
      case 'skipped':
        return TransferStatus.skipped;
      case 'failed':
        return TransferStatus.failed;
      case 'cancelled':
        return TransferStatus.cancelled;
      default:
        return TransferStatus.pending;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rootId': rootId,
      'localPath': localPath,
      'remotePath': remotePath,
      'fileName': fileName,
      'totalBytes': totalBytes,
      'transferredBytes': transferredBytes,
      'direction': direction,
      'status': status,
      'createdAt': createdAt,
      'errorMessage': errorMessage,
    };
  }
}
