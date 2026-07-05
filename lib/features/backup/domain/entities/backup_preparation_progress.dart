enum BackupPreparationPhase {
  scanningGallery,
  inspectingFiles,
  hashingFiles,
  preflighting,
  queueingUploads,
}

extension BackupPreparationPhaseLabels on BackupPreparationPhase {
  String get title => switch (this) {
    BackupPreparationPhase.scanningGallery => '正在扫描图库',
    BackupPreparationPhase.inspectingFiles => '正在检查本地文件',
    BackupPreparationPhase.hashingFiles => '正在计算文件指纹',
    BackupPreparationPhase.preflighting => '正在与服务端比对',
    BackupPreparationPhase.queueingUploads => '正在创建上传任务',
  };
}

class BackupPreparationProgress {
  const BackupPreparationProgress({
    required this.phase,
    required this.processedCount,
    required this.totalCount,
    this.detail,
  });

  final BackupPreparationPhase phase;
  final int processedCount;
  final int totalCount;
  final String? detail;
}
