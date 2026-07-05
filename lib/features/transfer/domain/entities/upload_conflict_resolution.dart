/// 文件输入：上传冲突处理动作
/// 文件职责：描述用户对重名上传的处理选择
/// 文件对外接口：UploadConflictResolution
/// 文件包含：UploadConflictResolution、UploadConflictResolutionPolicy
import '../../../../core/protocol/upload_contract.dart';

enum UploadConflictResolution { skip, overwrite, autoRename }

enum UploadConflictBatchResolution { skip, overwrite, autoRename, individually }

extension UploadConflictResolutionPolicy on UploadConflictResolution {
  UploadConflictPolicy? get uploadPolicy => switch (this) {
    UploadConflictResolution.skip => null,
    UploadConflictResolution.overwrite => UploadConflictPolicy.overwrite,
    UploadConflictResolution.autoRename => UploadConflictPolicy.autoRename,
  };
}
