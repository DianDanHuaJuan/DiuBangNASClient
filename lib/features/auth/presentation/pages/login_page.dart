/// 文件输入：登录页上下文、登录 Cubit、预填服务器信息
/// 文件职责：显示连接表单，处理扫码配对后的设备连接
/// 文件对外接口：LoginPage
/// 文件包含：LoginPage
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/service_locator.dart';
import '../../../../app/router/route_names.dart';
import '../../application/use_cases/bootstrap_device_session_use_case.dart';
import '../cubit/login_cubit.dart';
import '../cubit/login_state.dart';
import '../widgets/server_connect_form.dart';

class LoginPage extends StatefulWidget {
  final String? initialServerUrl;
  final String? initialServerName;
  final String? initialDiscoveryServerId;
  final String? initialDiscoveryCaSha256;
  final BootstrapDeviceSessionUseCase? bootstrapDeviceSessionUseCase;

  const LoginPage({
    super.key,
    this.initialServerUrl,
    this.initialServerName,
    this.initialDiscoveryServerId,
    this.initialDiscoveryCaSha256,
    this.bootstrapDeviceSessionUseCase,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Future<void> _handleLoginSuccess(BuildContext context, LoginSuccess state) async {
    final serverUrl = state.serverUrl;
    if (serverUrl.isNotEmpty) {
      await serviceLocator.setBaseUrl(serverUrl);
    }
    if (!context.mounted) {
      return;
    }
    context.go(RouteNames.home);
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapDeviceSessionUseCase =
        widget.bootstrapDeviceSessionUseCase ??
        serviceLocator.bootstrapDeviceSessionUseCase;

    return BlocProvider(
      create: (context) => LoginCubit(
        bootstrapDeviceSessionUseCase: bootstrapDeviceSessionUseCase,
      ),
      child: BlocListener<LoginCubit, LoginState>(
        listener: (context, state) {
          if (state is LoginSuccess) {
            unawaited(_handleLoginSuccess(context, state));
          } else if (state is LoginFailure) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leadingWidth: 150,
            leading: TextButton.icon(
              onPressed: () => context.go(RouteNames.serverList),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              label: const Text('选择服务器'),
            ),
            title: const Text('连接服务器'),
          ),
          body: ServerConnectForm(
            initialServerUrl: widget.initialServerUrl,
            initialServerName: widget.initialServerName,
            initialDiscoveryServerId: widget.initialDiscoveryServerId,
            initialDiscoveryCaSha256: widget.initialDiscoveryCaSha256,
          ),
        ),
      ),
    );
  }
}
