/// 文件输入：NAS 路径、上传冲突策略、服务端响应字段
/// 文件职责：定义上传冲突策略、上传结果与冲突异常
/// 文件对外接口：UploadConflictPolicy、UploadResult、UploadConflictException
/// 文件包含：UploadConflictPolicy、UploadResult、UploadConflictException
import '../path/nas_path.dart';

enum UploadConflictPolicy { fail, overwrite, autoRename }

extension UploadConflictPolicyWireValue on UploadConflictPolicy {
  String get wireValue => switch (this) {
    UploadConflictPolicy.fail => 'fail',
    UploadConflictPolicy.overwrite => 'overwrite',
    UploadConflictPolicy.autoRename => 'rename',
  };
}

class UploadResult {
  final NasPath targetPath;
  final String fileName;
  final bool overwritten;
  final bool autoRenamed;

  const UploadResult({
    required this.targetPath,
    required this.fileName,
    this.overwritten = false,
    this.autoRenamed = false,
  });

  factory UploadResult.forTarget(
    NasPath targetPath, {
    bool overwritten = false,
    bool autoRenamed = false,
  }) {
    final path = targetPath.path;
    final slashIndex = path.lastIndexOf('/');
    final fileName = slashIndex >= 0 ? path.substring(slashIndex + 1) : path;
    return UploadResult(
      targetPath: targetPath,
      fileName: fileName,
      overwritten: overwritten,
      autoRenamed: autoRenamed,
    );
  }
}

class UploadConflictException implements Exception {
  final NasPath targetPath;
  final String fileName;
  final String message;

  const UploadConflictException({
    required this.targetPath,
    required this.fileName,
    required this.message,
  });

  @override
  String toString() => message;
}
