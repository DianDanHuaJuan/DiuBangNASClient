/// 文件输入：文件分类类型
/// 文件职责：定义文件分类枚举（照片/视频/文档/其他）
/// 文件对外接口：FileCategory
/// 文件包含：FileCategory
enum FileCategory {
  photo,
  video,
  document,
  other;

  String get displayName {
    switch (this) {
      case FileCategory.photo:
        return '照片';
      case FileCategory.video:
        return '视频';
      case FileCategory.document:
        return '文档';
      case FileCategory.other:
        return '其他';
    }
  }

  static FileCategory? fromExtension(String ext) {
    String lowerExt = ext.toLowerCase();
    if (lowerExt.startsWith('.')) {
      lowerExt = lowerExt.substring(1);
    }
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(lowerExt)) {
      return FileCategory.photo;
    }
    if (['mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm', '3gp'].contains(lowerExt)) {
      return FileCategory.video;
    }
    if ([
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    ].contains(lowerExt)) {
      return FileCategory.document;
    }
    return null;
  }
}
