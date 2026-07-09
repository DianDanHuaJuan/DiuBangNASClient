import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nasclient/app/router/route_names.dart';
import 'package:nasclient/features/auth/application/use_cases/bootstrap_device_session_use_case.dart';
import 'package:nasclient/features/auth/domain/entities/auth_session_entity.dart';
import 'package:nasclient/features/auth/domain/entities/file_access_config_entity.dart';
import 'package:nasclient/features/auth/domain/entities/server_capabilities_entity.dart';
import 'package:nasclient/features/auth/domain/entities/server_profile_entity.dart';
import 'package:nasclient/features/auth/domain/repositories/auth_repository.dart';
import 'package:nasclient/features/auth/data/pairing_client.dart';
import 'package:nasclient/features/auth/presentation/pages/login_page.dart';
import 'package:nasclient/features/auth/presentation/widgets/server_connect_form.dart';
import 'package:nasclient/core/result/app_result.dart';

void main() {
  testWidgets('shows pairing-first connect form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          bootstrapDeviceSessionUseCase: BootstrapDeviceSessionUseCase(
            repository: _NoopAuthRepository(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('扫描连接二维码'), findsOneWidget);
    expect(find.text('管理员账密登录'), findsOneWidget);
    expect(find.text('管理员用户名'), findsNothing);
    expect(find.text('管理员密码'), findsNothing);
    expect(find.text('账密登录'), findsNothing);
    expect(find.byType(ServerConnectForm), findsOneWidget);
  });

  testWidgets('opens credential dialog from secondary button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          bootstrapDeviceSessionUseCase: BootstrapDeviceSessionUseCase(
            repository: _NoopAuthRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '服务器地址'),
      'https://192.168.1.10:8443',
    );
    await tester.tap(find.text('管理员账密登录'));
    await tester.pumpAndSettle();

    expect(find.text('管理员账密登录'), findsNWidgets(2));
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('returns to the server search page from the login page', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: RouteNames.login,
      routes: [
        GoRoute(
          path: RouteNames.serverList,
          builder: (_, _) => const Scaffold(body: Text('server-search-page')),
        ),
        GoRoute(
          path: RouteNames.login,
          builder: (_, _) => LoginPage(
            bootstrapDeviceSessionUseCase: BootstrapDeviceSessionUseCase(
              repository: _NoopAuthRepository(),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择服务器'));
    await tester.pumpAndSettle();

    expect(find.text('server-search-page'), findsOneWidget);
  });
}

class _NoopAuthRepository implements AuthRepository {
  @override
  Future<AppResult<AuthSessionEntity>> bootstrapDeviceSession({
    required PairingResult pairingResult,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> logout() async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<AuthSessionEntity>> restoreSession() async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<ServerCapabilitiesEntity>> getServerCapabilities() async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<ServerProfileEntity>> getServerProfile() async {
    throw UnimplementedError();
  }
}
