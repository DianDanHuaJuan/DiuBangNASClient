import 'file_entry_entity.dart';

class FileListPageEntity {
  const FileListPageEntity({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<FileEntryEntity> items;
  final bool hasMore;
  final String? nextCursor;
}
