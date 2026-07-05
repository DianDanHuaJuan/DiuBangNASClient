/// 文件输入：协议类型、WebDAV 配置
/// 文件职责：表达文件访问配置实体
/// 文件对外接口：FileAccessConfigEntity
/// 文件包含：FileAccessConfigEntity
class FileAccessConfigEntity {
  final String protocol;
  final Map<String, dynamic>? webdavConfig;

  const FileAccessConfigEntity({
    required this.protocol,
    this.webdavConfig,
  });

  String? get webdavBaseUrl => webdavConfig?['baseUrl'] as String?;
}
