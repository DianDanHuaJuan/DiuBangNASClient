/// 文件输入：配对结果
/// 文件职责：保存设备令牌并完成 bootstrap
/// 文件对外接口：BootstrapDeviceSessionUseCase
/// 文件包含：BootstrapDeviceSessionUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../data/pairing_client.dart';
import '../../domain/entities/auth_session_entity.dart';
import '../../domain/repositories/auth_repository.dart';

class BootstrapDeviceSessionUseCase
    implements UseCase<AppResult<AuthSessionEntity>, PairingResult> {
  final AuthRepository _repository;

  BootstrapDeviceSessionUseCase({required AuthRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<AuthSessionEntity>> call(PairingResult params) async {
    return _repository.bootstrapDeviceSession(pairingResult: params);
  }
}
