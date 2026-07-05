enum BackupMode { manualSelection, fullGallery }

extension BackupModeWireValue on BackupMode {
  String get wireValue => switch (this) {
    BackupMode.manualSelection => 'manual_selection',
    BackupMode.fullGallery => 'full_gallery',
  };

  static BackupMode fromWireValue(String value) {
    return switch (value) {
      'full_gallery' => BackupMode.fullGallery,
      _ => BackupMode.manualSelection,
    };
  }
}
