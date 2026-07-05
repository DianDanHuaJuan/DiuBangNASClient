/// 文件输入：ThumbnailRepository、LoadBatchThumbnailsParams
/// 文件职责：批量加载缩略图
/// 文件对外接口：LoadBatchThumbnailsUseCase
/// 文件包含：LoadBatchThumbnailsUseCase
import '../../../../core/use_case/use_case.dart';
import '../../domain/entities/thumbnail_item_entity.dart';
import '../../domain/repositories/thumbnail_repository.dart';
import '../params/load_batch_thumbnails_params.dart';

class LoadBatchThumbnailsUseCase
    implements UseCase<List<ThumbnailItemEntity>, LoadBatchThumbnailsParams> {
  final ThumbnailRepository _repository;

  LoadBatchThumbnailsUseCase({required ThumbnailRepository repository})
    : _repository = repository;

  @override
  Future<List<ThumbnailItemEntity>> call(
    LoadBatchThumbnailsParams params,
  ) async {
    final result = await _repository.loadBatchThumbnails(
      paths: params.paths,
      type: params.type,
    );

    return result.when(success: (data) => data, failure: (_) => []);
  }
}
