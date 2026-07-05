/// 文件输入：原图本地路径、文件名
/// 文件职责：封装原图保存到系统公共目录所需参数
/// 文件对外接口：SaveOriginalToPublicStorageParams
/// 文件包含：SaveOriginalToPublicStorageParams

/// 输入：原图本地路径、文件名。
/// 职责：统一描述保存原图到系统公共目录时的业务入参。
/// 对外接口：SaveOriginalToPublicStorageParams 值对象。
class SaveOriginalToPublicStorageParams {
  final String localPath;
  final String fileName;

  const SaveOriginalToPublicStorageParams({
    required this.localPath,
    required this.fileName,
  });
}
