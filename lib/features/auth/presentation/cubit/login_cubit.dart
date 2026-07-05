/// 文件输入：登录上下文、认证仓库
/// 文件职责：处理配对后的设备连接逻辑
/// 文件对外接口：LoginCubit
/// 文件包含：LoginCubit
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/network/nas_network_access_policy.dart';
import '../../application/use_cases/bootstrap_device_session_use_case.dart';
import '../../data/pairing_client.dart';
import 'login_state.dart';

class LoginCubit extends Cubit<LoginState> {
  final BootstrapDeviceSessionUseCase _bootstrapDeviceSessionUseCase;

  LoginCubit({required BootstrapDeviceSessionUseCase bootstrapDeviceSessionUseCase})
    : _bootstrapDeviceSessionUseCase = bootstrapDeviceSessionUseCase,
      super(LoginInitial());

  Future<void> connectAfterPairing(PairingResult pairingResult) async {
    emit(LoginLoading());
    try {
      final normalizedServerUrl = NasNetworkAccessPolicy.normalizeServerUrl(
        pairingResult.baseUrl,
      );
      final result = await _bootstrapDeviceSessionUseCase.call(pairingResult);
      result.when(
        success: (_) {
          emit(LoginSuccess(serverUrl: normalizedServerUrl));
        },
        failure: (failure) => emit(LoginFailure(failure.message)),
      );
    } on AppException catch (error) {
      emit(LoginFailure(error.message));
    } catch (e) {
      emit(LoginFailure(e.toString()));
    }
  }
}
