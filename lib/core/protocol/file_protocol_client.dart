/// 文件输入：目录路径、文件路径、流式文件读写参数
/// 文件职责：定义 WebDAV 文件协议统一抽象接口
/// 文件对外接口：FileProtocolClient
/// 文件包含：FileProtocolClient
import '../../features/files/domain/entities/file_entry_entity.dart';
import '../path/nas_path.dart';
import 'upload_contract.dart';

abstract class FileProtocolClient {
  Future<List<FileEntryEntity>> listDirectory(NasPath path);
  Future<void> createDirectory(NasPath path);
  Future<void> delete(NasPath path);
  Future<UploadResult> upload({
    required NasPath targetPath,
    required Stream<List<int>> sourceStream,
    required int totalSize,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    Map<String, String>? extraHeaders,
    void Function(int sent)? onProgress,
  });
  Future<Stream<List<int>>> download({
    required NasPath sourcePath,
    void Function(int received)? onProgress,
  });
  Future<bool> exists(NasPath path);
  Future<int> getFileSize(NasPath path);
}
