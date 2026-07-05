/// 文件输入：NAS 路径
/// 文件职责：定义预览仓库抽象接口
/// 文件对外接口：PreviewRepository
/// 文件包含：PreviewRepository
import '../../../../core/result/app_result.dart';
import '../../../../core/path/nas_path.dart';
import '../entities/preview_item_entity.dart';

abstract class PreviewRepository {
  Future<AppResult<PreviewItemEntity>> loadPreview(NasPath path);
}
