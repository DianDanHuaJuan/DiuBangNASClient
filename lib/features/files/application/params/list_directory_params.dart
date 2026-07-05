import '../../../../core/path/nas_path.dart';
import '../../domain/entities/file_category.dart';

class ListDirectoryParams {
  const ListDirectoryParams({
    required this.path,
    required this.category,
    this.cursor,
    this.limit = 120,
  });

  final NasPath path;
  final FileCategory category;
  final String? cursor;
  final int limit;
}
