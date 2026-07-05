import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/path/nas_path.dart';
import '../../domain/repositories/file_repository.dart';
import '../../domain/entities/batch_delete_result_entity.dart';

class BatchDeleteUseCase
    implements UseCase<AppResult<List<BatchDeleteResultEntity>>, List<NasPath>> {
  final FileRepository _repository;

  BatchDeleteUseCase({required FileRepository repository}) : _repository = repository;

  @override
  Future<AppResult<List<BatchDeleteResultEntity>>> call(List<NasPath> params) async {
    return await _repository.batchDelete(params);
  }
}
