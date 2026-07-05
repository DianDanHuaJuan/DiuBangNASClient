/// 文件输入：启动页上下文、路由解析 UseCase
/// 文件职责：显示极简启动过渡页，并在首帧后触发首屏路由计算
/// 文件对外接口：SplashPage
/// 文件包含：SplashPage
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/router/route_names.dart';
import '../../application/use_cases/resolve_start_route_use_case.dart';
import '../../../../core/use_case/no_params.dart';

class SplashPage extends StatefulWidget {
  final ResolveStartRouteUseCase resolveStartRouteUseCase;
  const SplashPage({super.key, required this.resolveStartRouteUseCase});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    developer.log('[SplashPage] initState — 准备在首帧后解析启动路由', name: 'startup');
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAndGo());
  }

  Future<void> _resolveAndGo() async {
    if (_didNavigate || !mounted) {
      developer.log(
        '[SplashPage] _resolveAndGo 跳过 — didNavigate=$_didNavigate mounted=$mounted',
        name: 'startup',
      );
      return;
    }
    _didNavigate = true;

    final t0 = DateTime.now();
    developer.log('[SplashPage] 开始解析启动路由...', name: 'startup');

    final result = await widget.resolveStartRouteUseCase.call(NoParams());

    final t1 = DateTime.now();
    final elapsedMs = t1.difference(t0).inMilliseconds;
    developer.log(
      '[SplashPage] 路由解析完成 — 目标:${result.route.name} 需恢复会话:${result.shouldRestoreSession} 耗时:${elapsedMs}ms',
      name: 'startup',
    );

    if (!mounted) {
      developer.log('[SplashPage] 路由解析后 widget 已卸载，放弃跳转', name: 'startup');
      return;
    }

    if (!mounted) {
      developer.log('[SplashPage] 路由解析后 widget 已卸载，放弃跳转', name: 'startup');
      return;
    }

    final t2 = DateTime.now();
    final totalMs = t2.difference(t0).inMilliseconds;

    if (result.route == StartRoute.home) {
      final location = Uri(
        path: RouteNames.home,
        queryParameters: result.shouldRestoreSession
            ? const <String, String>{'restoreSession': '1'}
            : null,
      ).toString();
      developer.log(
        '[SplashPage] → context.go(home) 总耗时:${totalMs}ms',
        name: 'startup',
      );
      context.go(location);
    } else {
      developer.log(
        '[SplashPage] → context.go(serverList) 总耗时:${totalMs}ms',
        name: 'startup',
      );
      context.go(RouteNames.serverList);
    }
  }

  @override
  Widget build(BuildContext context) {
    developer.log('[SplashPage] build — 渲染启动页', name: 'startup');
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
