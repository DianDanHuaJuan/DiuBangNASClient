/// 文件输入：NAS 路径
/// 文件职责：加载文件预览信息
/// 文件对外接口：LoadPreviewUseCase
/// 文件包含：LoadPreviewUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/path/nas_path.dart';
import '../../domain/entities/preview_item_entity.dart';
import '../../domain/repositories/preview_repository.dart';

class LoadPreviewUseCase
    implements UseCase<AppResult<PreviewItemEntity>, NasPath> {
  final PreviewRepository _repository;

  LoadPreviewUseCase({required PreviewRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<PreviewItemEntity>> call(NasPath path) async {
    return await _repository.loadPreview(path);
  }
}
