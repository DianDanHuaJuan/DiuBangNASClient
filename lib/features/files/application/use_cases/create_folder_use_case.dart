/// 文件输入：NAS 路径
/// 文件职责：创建新文件夹
/// 文件对外接口：CreateFolderUseCase
/// 文件包含：CreateFolderUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/path/nas_path.dart';
import '../../domain/repositories/file_repository.dart';

class CreateFolderUseCase implements UseCase<AppResult<void>, NasPath> {
  final FileRepository _repository;

  CreateFolderUseCase({required FileRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<void>> call(NasPath path) async {
    return await _repository.createFolder(path);
  }
}
