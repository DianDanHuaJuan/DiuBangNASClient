/// 文件输入：服务器地址输入控件
/// 文件职责：显示连接服务器的配对表单 UI
/// 文件对外接口：ServerConnectForm
/// 文件包含：ServerConnectForm
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/service_locator.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/network/nas_network_access_policy.dart';
import '../../../../core/node/server_display_name_resolver.dart';
import '../cubit/login_cubit.dart';
import '../cubit/login_state.dart';
import 'package:nasclient/features/auth/presentation/widgets/qr_crypto.dart';
import 'package:nasclient/features/auth/presentation/widgets/qr_scanner_page.dart';

class ServerConnectForm extends StatefulWidget {
  final String? initialServerUrl;
  final String? initialServerName;
  final String? initialDiscoveryServerId;
  final String? initialDiscoveryCaSha256;

  const ServerConnectForm({
    super.key,
    this.initialServerUrl,
    this.initialServerName,
    this.initialDiscoveryServerId,
    this.initialDiscoveryCaSha256,
  });

  @override
  State<ServerConnectForm> createState() => ServerConnectFormState();
}

class ServerConnectFormState extends State<ServerConnectForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverUrlController;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(
      text: widget.initialServerUrl ?? '',
    )..addListener(_handleServerChange);
  }

  @override
  void dispose() {
    _serverUrlController.removeListener(_handleServerChange);
    _serverUrlController.dispose();
    super.dispose();
  }

  void _handleServerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _applyPairingToken(String token) async {
    try {
      _setStatus('正在处理 HTTPS 配对信息…');
      final payload = await parsePairingQrToken(token);
      final discoveryServerId = widget.initialDiscoveryServerId?.trim();
      final discoveryCaSha256 = normalizeSha256Fingerprint(
        widget.initialDiscoveryCaSha256 ?? '',
      );

      if (discoveryServerId != null &&
          discoveryServerId.isNotEmpty &&
          discoveryServerId != payload.serverId) {
        _setStatus(null);
        throw Exception('二维码中的服务器标识与当前发现结果不一致');
      }

      await serviceLocator.trustedServerStore.trustServer(
        serverId: payload.serverId,
        serverName: payload.serverName ?? '',
        baseUrl: payload.baseUrl,
        rootCaPem: payload.rootCaPem,
        caSha256: payload.caSha256,
        leafSha256: payload.leafSha256,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _serverUrlController.text = payload.baseUrl;
        _statusMessage = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('HTTPS 配对成功')));
    } catch (e) {
      _setStatus(null);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('配对失败: $e')));
      }
    }
  }

  Future<void> _applyPairingV3Token(String token) async {
    try {
      final qrData = await serviceLocator.pairingClient.parsePairingQrToken(
        token,
      );
      final discoveryServerId = widget.initialDiscoveryServerId?.trim();
      final discoveryCaSha256 = normalizeSha256Fingerprint(
        widget.initialDiscoveryCaSha256 ?? '',
      );

      if (discoveryServerId != null &&
          discoveryServerId.isNotEmpty &&
          discoveryServerId != qrData.serverId) {
        _setStatus(null);
        throw const AppException(
          code: 'SERVER_ID_MISMATCH',
          message: '二维码中的服务器标识与当前发现结果不一致',
        );
      }

      _setStatus('正在建立安全连接并注册设备…');
      final pairingResult = await serviceLocator.pairingClient.completePairing(
        token,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _serverUrlController.text = pairingResult.baseUrl;
        _statusMessage = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('配对成功，正在连接')));
      await context.read<LoginCubit>().connectAfterPairing(pairingResult);
    } on AppException catch (error) {
      _setStatus(null);
      if (mounted) {
        final errorDetails =
            '错误码: ${error.code}\n'
            '错误信息: ${error.message}';

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('配对失败'),
            content: SingleChildScrollView(
              child: Text(
                errorDetails,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _setStatus(null);
      if (mounted) {
        final errorMsg = '配对失败: $e';

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('配对失败'),
            content: SingleChildScrollView(
              child: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _applyQrToken(String token) async {
    final normalizedToken = token.trim();
    if (isPairingV3QrToken(normalizedToken)) {
      await _applyPairingV3Token(normalizedToken);
      return;
    }
    if (isPairingQrToken(normalizedToken)) {
      await _applyPairingToken(normalizedToken);
      return;
    }
    _setStatus(null);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂不支持该二维码类型')));
    }
  }

  Future<void> _handleScanQr() async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const QrScannerPage()),
    );
    if (token == null || token.isEmpty) return;
    _setStatus('正在解析配对二维码…');
    await _applyQrToken(token);
  }

  void _setStatus(String? message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
  }

  String _serverLabel() {
    return ServerDisplayNameResolver.resolve(
      mdnsServiceName: widget.initialServerName,
      qrName: widget.initialServerName,
    );
  }

  Widget _buildServerCard(BuildContext context) {
    final theme = Theme.of(context);
    final description = _serverUrlController.text.trim().isEmpty
        ? '请通过下方按钮，扫描服务端配对二维码以完成设备注册与连接。'
        : _serverUrlController.text.trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.storage_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_serverLabel(), style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    required String? Function(String?) validator,
    Iterable<String>? autofillHints,
  }) {
    return TextFormField(
      controller: controller,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(icon),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginCubit, LoginState>(
      builder: (context, state) {
        final isLoading = state is LoginLoading;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  '请通过下方按钮，扫描服务端配对二维码以完成设备注册与连接。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_statusMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1FB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF2B6CB0),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: const Color(0xFF2B6CB0),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildServerCard(context),
                const SizedBox(height: 18),
                _buildField(
                  controller: _serverUrlController,
                  labelText: '服务器地址',
                  hintText: 'https://nas.local:8080',
                  icon: Icons.link_rounded,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入服务器地址';
                    }
                    try {
                      NasNetworkAccessPolicy.normalizeServerUrl(value);
                    } on AppException catch (error) {
                      return error.message;
                    }
                    return null;
                  },
                  autofillHints: const [AutofillHints.url],
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: isLoading ? null : _handleScanQr,
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(isLoading ? '正在连接…' : '扫描连接二维码'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
