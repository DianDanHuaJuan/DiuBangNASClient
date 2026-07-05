import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nasclient/app/di/service_locator.dart';
import 'package:nasclient/app/router/route_names.dart';
import 'package:nasclient/core/session/server_availability_controller.dart';
import 'package:nasclient/core/widgets/offline_resource_gate.dart';

void main() {
  late ServerAvailabilityController controller;

  setUp(() {
    controller = ServerAvailabilityController();
    controller.startMonitoring();
    serviceLocator.unifiedNodeStore.clear();
    serviceLocator.unifiedNodeStore.applySessionData(
      serverId: 'server-1',
      serverName: '测试 NAS',
      serverVersion: '1.0.0',
      serverStatus: 'online',
      serverUrl: 'http://192.168.1.8:8080',
      username: 'owner',
      password: 'password',
      protocol: 'webdav',
      rootId: 'fs',
      rootName: '文件',
    );
  });

  tearDown(serviceLocator.unifiedNodeStore.clear);

  testWidgets('hides offline gate during initial connection grace', (
    tester,
  ) async {
    controller.startMonitoring(
      initialStatus: ServerAvailabilityStatus.offline,
      awaitingInitialConnection: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              OfflineResourceGate(
                controller: controller,
                onReconnect: () async {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('服务器当前离线'), findsNothing);
    expect(find.text('重新连接'), findsNothing);

    controller.markOnline();
    await tester.pump();

    expect(find.text('服务器当前离线'), findsNothing);
  });

  testWidgets('shows the offline gate and triggers reconnect', (tester) async {
    var reconnectCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              OfflineResourceGate(
                controller: controller,
                onReconnect: () async {
                  reconnectCount += 1;
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('服务器当前离线'), findsNothing);

    controller.markOffline();
    await tester.pump();

    expect(find.text('服务器当前离线'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);

    await tester.tap(find.text('重新连接'));
    await tester.pump();

    expect(reconnectCount, 1);

    controller.markOnline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('服务器当前离线'), findsNothing);
  });

  testWidgets('returns to the login page with current server info', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: RouteNames.home,
      routes: [
        GoRoute(
          path: RouteNames.home,
          builder: (_, _) => Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(),
                OfflineResourceGate(
                  controller: controller,
                  onReconnect: () async {},
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: RouteNames.login,
          builder: (_, state) => Scaffold(
            body: Text(
              'login:${state.uri.queryParameters['serverUrl']}:${state.uri.queryParameters['serverName']}',
            ),
          ),
        ),
        GoRoute(
          path: RouteNames.serverList,
          builder: (_, _) => const Scaffold(body: Text('server-search-page')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    controller.markOffline();
    await tester.pumpAndSettle();

    await tester.tap(find.text('返回登录页'));
    await tester.pumpAndSettle();

    expect(find.text('login:http://192.168.1.8:8080:测试 NAS'), findsOneWidget);
  });

  testWidgets('returns to the server search page', (tester) async {
    final router = GoRouter(
      initialLocation: RouteNames.home,
      routes: [
        GoRoute(
          path: RouteNames.home,
          builder: (_, _) => Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(),
                OfflineResourceGate(
                  controller: controller,
                  onReconnect: () async {},
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: RouteNames.login,
          builder: (_, _) => const Scaffold(body: Text('login-page')),
        ),
        GoRoute(
          path: RouteNames.serverList,
          builder: (_, _) => const Scaffold(body: Text('server-search-page')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    controller.markOffline();
    await tester.pumpAndSettle();

    await tester.tap(find.text('返回搜索页'));
    await tester.pumpAndSettle();

    expect(find.text('server-search-page'), findsOneWidget);
  });
}
