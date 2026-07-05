/// 文件输入：NAS 路径
/// 文件职责：删除文件或目录
/// 文件对外接口：DeleteFileUseCase
/// 文件包含：DeleteFileUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/path/nas_path.dart';
import '../../domain/repositories/file_repository.dart';

class DeleteFileUseCase implements UseCase<AppResult<void>, NasPath> {
  final FileRepository _repository;

  DeleteFileUseCase({required FileRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<void>> call(NasPath path) async {
    return await _repository.deleteFile(path);
  }
}
