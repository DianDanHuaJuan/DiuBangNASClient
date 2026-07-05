import '../../../../core/path/nas_path.dart';
import '../../domain/entities/file_category.dart';
import '../../domain/entities/file_entry_entity.dart';

abstract class FileBrowserState {
  const FileBrowserState();
}

class FileBrowserInitial extends FileBrowserState {
  const FileBrowserInitial();
}

class FileBrowserLoading extends FileBrowserState {
  const FileBrowserLoading();
}

class FileBrowserLoaded extends FileBrowserState {
  const FileBrowserLoaded({
    required this.allFiles,
    required this.filteredFiles,
    required this.mediaFiles,
    required this.currentPath,
    required this.currentRootId,
    required this.currentRootWritable,
    required this.currentCategory,
    this.selectionMode = false,
    this.selectedPaths = const <String>{},
    this.hasMore = false,
    this.nextCursor,
    this.isLoadingMore = false,
    this.message,
    this.thumbnailVersion = 0,
  });

  final List<FileEntryEntity> allFiles;
  final List<FileEntryEntity> filteredFiles;
  final List<FileEntryEntity> mediaFiles;
  final NasPath currentPath;
  final String currentRootId;
  final bool currentRootWritable;
  final FileCategory currentCategory;
  final bool selectionMode;
  final Set<String> selectedPaths;
  final bool hasMore;
  final String? nextCursor;
  final bool isLoadingMore;
  final String? message;
  final int thumbnailVersion;

  FileBrowserLoaded copyWith({
    List<FileEntryEntity>? allFiles,
    List<FileEntryEntity>? filteredFiles,
    List<FileEntryEntity>? mediaFiles,
    NasPath? currentPath,
    String? currentRootId,
    bool? currentRootWritable,
    FileCategory? currentCategory,
    bool? selectionMode,
    Set<String>? selectedPaths,
    bool? hasMore,
    String? nextCursor,
    bool? isLoadingMore,
    String? message,
    int? thumbnailVersion,
  }) {
    return FileBrowserLoaded(
      allFiles: allFiles ?? this.allFiles,
      filteredFiles: filteredFiles ?? this.filteredFiles,
      mediaFiles: mediaFiles ?? this.mediaFiles,
      currentPath: currentPath ?? this.currentPath,
      currentRootId: currentRootId ?? this.currentRootId,
      currentRootWritable: currentRootWritable ?? this.currentRootWritable,
      currentCategory: currentCategory ?? this.currentCategory,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor ?? this.nextCursor,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      message: message,
      thumbnailVersion: thumbnailVersion ?? this.thumbnailVersion,
    );
  }
}

class FileBrowserError extends FileBrowserState {
  const FileBrowserError(this.message);

  final String message;
}
