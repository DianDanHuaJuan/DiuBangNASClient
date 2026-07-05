/// 文件输入：启动阶段上下文
/// 文件职责：计算启动页应该跳转的目标路由
/// 文件对外接口：ResolveStartRouteUseCase
/// 文件包含：ResolveStartRouteUseCase, StartRoute, StartRouteResolution
import '../../../../core/network/nas_network_access_policy.dart';
import '../../../../core/node/unified_node.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../../core/use_case/use_case.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../auth/presentation/cubit/server_selection_cubit.dart';

enum StartRoute { serverList, home }

class StartRouteResolution {
  const StartRouteResolution({
    required this.route,
    this.shouldRestoreSession = false,
  });

  final StartRoute route;
  final bool shouldRestoreSession;
}

class ResolveStartRouteUseCase extends UseCase<StartRouteResolution, NoParams> {
  ResolveStartRouteUseCase({
    required KeyValueStore keyValueStore,
    required AuthLocalDataSource authLocalDataSource,
    ServerOnlineProbe? onlineProbe,
  }) : _keyValueStore = keyValueStore,
       _authLocalDataSource = authLocalDataSource,
       _onlineProbe = onlineProbe ?? ServerSelectionCubit.probeServerOnline;

  final KeyValueStore _keyValueStore;
  final AuthLocalDataSource _authLocalDataSource;
  final ServerOnlineProbe _onlineProbe;

  @override
  Future<StartRouteResolution> call(NoParams params) async {
    final lastUrl = _keyValueStore.getLastServerUrl()?.trim() ?? '';
    if (lastUrl.isEmpty) {
      return const StartRouteResolution(route: StartRoute.serverList);
    }

    final savedServer = _findSavedServer(lastUrl);
    if (savedServer == null) {
      return const StartRouteResolution(route: StartRoute.serverList);
    }

    if (!await _authLocalDataSource.hasRecoverableSession()) {
      return const StartRouteResolution(route: StartRoute.serverList);
    }

    final probeUrl = savedServer.network.connectBaseUrl?.trim().isNotEmpty == true
        ? savedServer.network.connectBaseUrl!.trim()
        : lastUrl;
    final online = await _onlineProbe(probeUrl);
    if (!online) {
      return const StartRouteResolution(route: StartRoute.serverList);
    }

    return const StartRouteResolution(
      route: StartRoute.home,
      shouldRestoreSession: true,
    );
  }

  UnifiedNode? _findSavedServer(String lastUrl) {
    final normalizedLastUrl = NasNetworkAccessPolicy.normalizeServerUrl(lastUrl);
    for (final server in _keyValueStore.getServerNodes()) {
      final url = server.network.connectBaseUrl?.trim() ?? '';
      if (url.isEmpty) {
        continue;
      }
      if (NasNetworkAccessPolicy.normalizeServerUrl(url) == normalizedLastUrl) {
        return server;
      }
    }
    return null;
  }
}
