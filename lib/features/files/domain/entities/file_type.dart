/// 文件输入：文件类型枚举值
/// 文件职责：统一表达文件类型，用于区分文件和目录
/// 文件对外接口：FileType
/// 文件包含：FileType
enum FileType {
  file,
  directory;

  static FileType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'file':
      case 'f':
        return FileType.file;
      case 'directory':
      case 'dir':
      case 'd':
        return FileType.directory;
      default:
        return FileType.file;
    }
  }

  String get value {
    switch (this) {
      case FileType.file:
        return 'file';
      case FileType.directory:
        return 'directory';
    }
  }
}
