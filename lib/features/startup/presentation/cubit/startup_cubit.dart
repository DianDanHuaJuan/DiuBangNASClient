/// 文件输入：解析启动路由 UseCase
/// 文件职责：调用 UseCase 获取目标路由并映射成状态
/// 文件对外接口：StartupCubit
/// 文件包含：StartupCubit
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../application/use_cases/resolve_start_route_use_case.dart';
import '../../../../core/use_case/no_params.dart';
import 'startup_state.dart';

class StartupCubit extends Cubit<StartupState> {
  final ResolveStartRouteUseCase _resolveStartRouteUseCase;

  StartupCubit({required ResolveStartRouteUseCase resolveStartRouteUseCase})
    : _resolveStartRouteUseCase = resolveStartRouteUseCase,
      super(StartupInitial());

  Future<void> checkStartRoute() async {
    emit(StartupLoading());

    final result = await _resolveStartRouteUseCase.call(NoParams());

    if (result.route == StartRoute.home) {
      emit(
        StartupRedirectToHome(
          shouldRestoreSession: result.shouldRestoreSession,
        ),
      );
    } else {
      emit(StartupRedirectToServerList());
    }
  }
}
