import '../../../../core/path/nas_path.dart';
import '../../../../core/result/app_result.dart';
import '../../application/params/list_directory_params.dart';
import '../entities/batch_delete_result_entity.dart';
import '../entities/file_list_page_entity.dart';

abstract class FileRepository {
  Future<AppResult<FileListPageEntity>> listDirectory(
    ListDirectoryParams params,
  );
  Future<AppResult<void>> createFolder(NasPath path);
  Future<AppResult<void>> deleteFile(NasPath path);
  Future<AppResult<List<BatchDeleteResultEntity>>> batchDelete(
    List<NasPath> paths,
  );
}
