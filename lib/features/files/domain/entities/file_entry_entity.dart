/// 文件输入：文件名、路径、类型、大小、修改时间
/// 文件职责：表达目录项，统一业务层的文件实体
/// 文件对外接口：FileEntryEntity
/// 文件包含：FileEntryEntity
import 'file_type.dart';

class FileEntryEntity {
  final String name;
  final String path;
  final FileType type;
  final int size;
  final DateTime? modifiedAt;

  const FileEntryEntity({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    this.modifiedAt,
  });

  bool get isDirectory => type == FileType.directory;
  bool get isFile => type == FileType.file;

  bool get isImage {
    if (!isFile) return false;
    final ext = extension;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  bool get isVideo {
    if (!isFile) return false;
    final ext = extension;
    return ['mp4', 'mkv', 'avi', 'mov', 'webm', '3gp'].contains(ext);
  }

  String get extension {
    if (!isFile) return '';
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  String get formattedSize {
    if (isDirectory) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
