/// 文件输入：bootstrap API 响应 JSON
/// 文件职责：解析 bootstrap 响应 DTO
/// 文件对外接口：BootstrapResponseDto
/// 文件包含：BootstrapResponseDto
import '../../../../core/auth/root_info.dart';

class BootstrapResponseDto {
  final String serverId;
  final String serverName;
  final String serverVersion;
  final String serverStatus;
  final String? platform;
  final String protocol;
  final String rootId;
  final String rootName;
  final List<RootInfo> roots;
  final Map<String, dynamic>? webdavConfig;
  final Map<String, dynamic>? capabilities;

  const BootstrapResponseDto({
    required this.serverId,
    required this.serverName,
    required this.serverVersion,
    required this.serverStatus,
    this.platform,
    required this.protocol,
    required this.rootId,
    required this.rootName,
    required this.roots,
    this.webdavConfig,
    this.capabilities,
  });

  factory BootstrapResponseDto.fromJson(Map<String, dynamic> json) {
    final server = json['server'] as Map<String, dynamic>?;
    final fileAccess = json['fileAccess'] as Map<String, dynamic>?;
    final rootsJson = fileAccess?['roots'];
    final roots = rootsJson is List
        ? rootsJson
              .whereType<Map<String, dynamic>>()
              .map(RootInfo.fromJson)
              .toList()
        : const <RootInfo>[];
    final primaryRoot = roots.isNotEmpty ? roots.first : null;

    return BootstrapResponseDto(
      serverId: server?['id'] as String? ?? json['serverId'] as String? ?? '',
      serverName:
          server?['name'] as String? ?? json['serverName'] as String? ?? '',
      serverVersion:
          server?['version'] as String? ??
          json['serverVersion'] as String? ??
          '',
      serverStatus:
          server?['status'] as String? ?? json['serverStatus'] as String? ?? '',
      platform:
          server?['platform'] as String? ?? json['platform'] as String?,
      protocol:
          fileAccess?['protocol'] as String? ??
          json['protocol'] as String? ??
          'webdav',
      rootId: json['rootId'] as String? ?? primaryRoot?.id ?? '',
      rootName: json['rootName'] as String? ?? primaryRoot?.name ?? '',
      roots: roots,
      webdavConfig:
          fileAccess?['webdav'] as Map<String, dynamic>? ??
          json['webdav'] as Map<String, dynamic>?,
      capabilities: json['capabilities'] as Map<String, dynamic>?,
    );
  }
}
