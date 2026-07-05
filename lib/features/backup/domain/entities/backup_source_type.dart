/// 文件输入：备份来源枚举值
/// 文件职责：区分立即备份中的来源类型，便于页面提示和策略分流
/// 文件对外接口：BackupSourceType
/// 文件包含：BackupSourceType
enum BackupSourceType {
  media,
  file,
  directoryExpandedFile;

  String get label => switch (this) {
    BackupSourceType.media => '图库',
    BackupSourceType.file => '文件',
    BackupSourceType.directoryExpandedFile => '目录',
  };
}
