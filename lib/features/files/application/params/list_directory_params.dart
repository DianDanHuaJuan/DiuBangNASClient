import '../../../../core/path/nas_path.dart';
import '../../domain/entities/file_category.dart';

class ListDirectoryParams {
  const ListDirectoryParams({
    required this.path,
    required this.category,
    this.cursor,
    this.limit = 120,
    this.sortBy,
    this.sortOrder,
  });

  final NasPath path;
  final FileCategory category;
  final String? cursor;
  final int limit;
  /// 排序字段：'modified'（默认） | 'size'
  final String? sortBy;
  /// 排序方向：'desc'（默认） | 'asc'
  final String? sortOrder;
}
