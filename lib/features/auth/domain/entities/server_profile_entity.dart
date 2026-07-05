/// 文件输入：服务器 ID、名称、版本、状态
/// 文件职责：表达服务器基础信息实体
/// 文件对外接口：ServerProfileEntity
/// 文件包含：ServerProfileEntity
class ServerProfileEntity {
  final String serverId;
  final String serverName;
  final String serverVersion;
  final String serverStatus;
  final String? platform;

  const ServerProfileEntity({
    required this.serverId,
    required this.serverName,
    required this.serverVersion,
    required this.serverStatus,
    this.platform,
  });
}
