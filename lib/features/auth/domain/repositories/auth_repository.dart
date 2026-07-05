/// 文件输入：服务器连接参数
/// 文件职责：定义认证仓库抽象接口，规范认证业务
/// 文件对外接口：AuthRepository
/// 文件包含：AuthRepository
import '../../../../core/result/app_result.dart';
import '../../data/pairing_client.dart';
import '../entities/auth_session_entity.dart';
import '../entities/server_profile_entity.dart';
import '../entities/server_capabilities_entity.dart';

abstract class AuthRepository {
  Future<AppResult<AuthSessionEntity>> bootstrapDeviceSession({
    required PairingResult pairingResult,
  });
  Future<AppResult<AuthSessionEntity>> restoreSession();
  Future<AppResult<void>> logout();
  Future<AppResult<ServerProfileEntity>> getServerProfile();
  Future<AppResult<ServerCapabilitiesEntity>> getServerCapabilities();
}
