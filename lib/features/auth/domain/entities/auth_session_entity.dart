/// 文件输入：服务器信息、文件访问配置、能力矩阵、根目录信息
/// 文件职责：表达完整认证会话实体
/// 文件对外接口：AuthSessionEntity
/// 文件包含：AuthSessionEntity
import 'server_profile_entity.dart';
import 'file_access_config_entity.dart';
import 'server_capabilities_entity.dart';

class AuthSessionEntity {
  final ServerProfileEntity serverProfile;
  final FileAccessConfigEntity fileAccess;
  final ServerCapabilitiesEntity capabilities;
  final String rootId;
  final String rootName;

  const AuthSessionEntity({
    required this.serverProfile,
    required this.fileAccess,
    required this.capabilities,
    required this.rootId,
    required this.rootName,
  });
}
