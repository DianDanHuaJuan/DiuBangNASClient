import '../../../../core/result/app_result.dart';
import '../../../../core/use_case/use_case.dart';
import '../params/list_directory_params.dart';
import '../../domain/entities/file_list_page_entity.dart';
import '../../domain/repositories/file_repository.dart';

class ListDirectoryUseCase
    implements UseCase<AppResult<FileListPageEntity>, ListDirectoryParams> {
  ListDirectoryUseCase({required FileRepository repository})
    : _repository = repository;

  final FileRepository _repository;

  @override
  Future<AppResult<FileListPageEntity>> call(ListDirectoryParams params) async {
    return _repository.listDirectory(params);
  }
}
