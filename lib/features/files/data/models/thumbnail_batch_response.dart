import '../../domain/entities/thumbnail_item_entity.dart';

class ThumbnailBatchResponse {
  const ThumbnailBatchResponse({
    required this.items,
    required this.failedPaths,
  });

  final List<ThumbnailItemEntity> items;
  final List<String> failedPaths;
}
