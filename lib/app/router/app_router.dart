/// 文件输入：RouteNames、启动态与登录态跳转规则
/// 文件职责：集中定义页面路由表和跳转规则
/// 文件对外接口：buildAppRouter
import 'package:go_router/go_router.dart';
import 'route_names.dart';
import '../../app/di/service_locator.dart';
import '../../features/startup/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/server_selection_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/home/presentation/pages/home_shell_page.dart';
import '../../features/startup/application/use_cases/resolve_start_route_use_case.dart';

GoRouter buildAppRouter({ResolveStartRouteUseCase? resolveStartRouteUseCase}) {
  return GoRouter(
    initialLocation: RouteNames.splash,
    routes: [
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => SplashPage(
          resolveStartRouteUseCase: resolveStartRouteUseCase ?? serviceLocator.resolveStartRouteUseCase,
        ),
      ),
      GoRoute(
        path: RouteNames.serverList,
        builder: (context, state) => const ServerSelectionPage(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => LoginPage(
          initialServerUrl: state.uri.queryParameters['serverUrl'],
          initialServerName: state.uri.queryParameters['serverName'],
          initialDiscoveryServerId: state.uri.queryParameters['serverId'],
          initialDiscoveryCaSha256: state.uri.queryParameters['caSha256'],
        ),
      ),
      GoRoute(
        path: RouteNames.home,
        builder: (context, state) => HomeShellPage(
          shouldRestoreSession:
              state.uri.queryParameters['restoreSession'] == '1',
        ),
      ),
    ],
    redirect: (context, state) {
      return null;
    },
  );
}
