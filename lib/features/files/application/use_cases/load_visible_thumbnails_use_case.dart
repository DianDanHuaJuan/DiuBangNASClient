/// 文件输入：ThumbnailRepository、LoadVisibleThumbnailsParams
/// 文件职责：逐批渐进加载可见区域的缩略图，每完成一个小批次通过 Stream 通知调用方
/// 文件对外接口：LoadVisibleThumbnailsUseCase
/// 文件包含：LoadVisibleThumbnailsUseCase
import '../../domain/repositories/thumbnail_repository.dart';
import '../params/load_visible_thumbnails_params.dart';

/// 输入：LoadVisibleThumbnailsParams（路径列表、缩略图类型）
/// 职责：委托 Repository 逐批加载缩略图，返回 Stream 以支持渐进渲染
/// 对外接口：call() 返回 Stream，每个事件为本次小批次加载的数量
class LoadVisibleThumbnailsUseCase {
  final ThumbnailRepository _repository;

  LoadVisibleThumbnailsUseCase({required ThumbnailRepository repository})
    : _repository = repository;

  Stream<int> call(LoadVisibleThumbnailsParams params) {
    return _repository
        .loadThumbnailsProgressively(paths: params.paths, type: params.type)
        .map((batch) => batch.length);
  }
}
