/// 文件输入：备份入口点击事件与页面上下文中的备份依赖
/// 文件职责：显示设置页面，并提供文件备份等功能入口
/// 文件对外接口：SettingsPage
/// 文件包含：SettingsPage、_SettingsEntryTile
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/device/client_identity_service.dart';
import '../../../../core/device/local_media_picker.dart';
import '../../../../core/node/device_alias_constraints.dart';
import '../../../../core/profile/device_identity_store.dart';
import '../../../../core/profile/user_profile_store.dart';
import '../../../../features/device_identity/domain/device_identity_service.dart';
import '../../../../features/device_identity/presentation/pages/device_avatar_crop_page.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../benchmark/benchmark_feature.dart';
import '../../../backup/presentation/cubit/backup_cubit.dart';
import '../../../backup/presentation/pages/backup_page.dart';
import '../../../transfer/presentation/cubit/transfer_cubit.dart';

class SettingsPage extends StatelessWidget {
  final VoidCallback? onBackupTap;
  final DeviceIdentityStore? userProfileStore;
  final ClientIdentityService? clientIdentityService;
  final DeviceIdentityService? deviceIdentityService;

  const SettingsPage({
    super.key,
    this.onBackupTap,
    this.userProfileStore,
    this.clientIdentityService,
    this.deviceIdentityService,
  });

  void _openBackupPage(BuildContext context) {
    if (onBackupTap != null) {
      onBackupTap!();
      return;
    }

    final backupCubit = context.read<BackupCubit>();
    final transferCubit = context.read<TransferCubit>();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider<BackupCubit>.value(value: backupCubit),
            BlocProvider<TransferCubit>.value(value: transferCubit),
          ],
          child: const BackupPage(),
        ),
      ),
    );
  }

  void _openBenchmarkPage(BuildContext context) {
    BenchmarkFeature.openPage(context);
  }

  @override
  Widget build(BuildContext context) {
    final profileStore =
        userProfileStore ?? serviceLocator.userProfileStore;
    final identityService =
        clientIdentityService ?? serviceLocator.clientIdentityService;
    final deviceIdentity =
        deviceIdentityService ?? serviceLocator.deviceIdentityService;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 24),
              _DeviceIdentitySettingsTile(
                identityStore: profileStore,
                clientIdentityService: identityService,
                deviceIdentityService: deviceIdentity,
              ),
              const SizedBox(height: 24),
              _SettingsEntryTile(
                icon: Icons.backup_table_outlined,
                title: '文件备份',
                onTap: () => _openBackupPage(context),
              ),
              if (BenchmarkFeature.enabled) ...[
                const SizedBox(height: 16),
                _SettingsEntryTile(
                  icon: Icons.speed_rounded,
                  title: '传输测速',
                  subtitle: '独立 benchmark 模块，用于 direct / relay 诊断测速',
                  onTap: () => _openBenchmarkPage(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceIdentitySettingsTile extends StatefulWidget {
  final DeviceIdentityStore identityStore;
  final ClientIdentityService clientIdentityService;
  final DeviceIdentityService deviceIdentityService;

  const _DeviceIdentitySettingsTile({
    required this.identityStore,
    required this.clientIdentityService,
    required this.deviceIdentityService,
  });

  @override
  State<_DeviceIdentitySettingsTile> createState() =>
      _DeviceIdentitySettingsTileState();
}

class _DeviceIdentitySettingsTileState
    extends State<_DeviceIdentitySettingsTile> {
  static const _localMediaPicker = LocalMediaPicker();
  String? _deviceName;
  String? _avatarPath;
  String? _displayAlias;

  @override
  void initState() {
    super.initState();
    _avatarPath = widget.identityStore.avatarPath;
    _displayAlias = widget.identityStore.displayAlias;
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final name = await widget.clientIdentityService.getDeviceName();
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceName = name;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceName = '本机';
      });
    }
  }

  String get _resolvedDisplayName {
    final alias = _displayAlias?.trim();
    if (alias != null && alias.isNotEmpty) {
      return alias;
    }
    final hardwareName = _deviceName?.trim();
    if (hardwareName != null && hardwareName.isNotEmpty) {
      return hardwareName;
    }
    return '本机';
  }

  Future<void> _pickAvatar() async {
    final result = await _localMediaPicker.pickMediaFiltered(
      context,
      maxAssets: 1,
      includeImages: true,
      includeVideos: false,
    );
    if (!mounted || result.items.isEmpty) {
      return;
    }
    final croppedBytes = await DeviceAvatarCropPage.open(
      context,
      result.items.first.localPath,
    );
    if (!mounted || croppedBytes == null) {
      return;
    }
    try {
      await widget.deviceIdentityService.setAvatarFromBytes(croppedBytes);
      if (!mounted) {
        return;
      }
      final latestPath = widget.identityStore.avatarPath;
      final previousPath = _avatarPath;
      if (previousPath != null &&
          previousPath.isNotEmpty &&
          previousPath != latestPath) {
        PaintingBinding.instance.imageCache.evict(FileImage(File(previousPath)));
      }
      setState(() => _avatarPath = latestPath);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像保存失败：$error')),
      );
    }
  }

  Future<void> _clearAvatar() async {
    try {
      await widget.deviceIdentityService.clearAvatar();
      if (!mounted) {
        return;
      }
      setState(() => _avatarPath = null);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清除头像失败：$error')),
      );
    }
  }

  Future<void> _editDisplayAlias() async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return _EditDisplayAliasDialog(initialAlias: _displayAlias);
      },
    );
    if (result == null || !mounted) {
      return;
    }
    final validationError = DeviceAliasConstraints.validate(result);
    if (validationError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(validationError)),
        );
      }
      return;
    }
    try {
      await widget.deviceIdentityService.updateDisplayAlias(result);
      if (!mounted) {
        return;
      }
      setState(() => _displayAlias = widget.identityStore.displayAlias);
    } catch (error) {
      if (mounted) {
        final message = error is ArgumentError
            ? error.message?.toString() ?? '名称无效'
            : '名称保存失败：$error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  Future<void> _showIdentityOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('设置头像'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAvatar();
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('设置名称'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editDisplayAlias();
                },
              ),
              if (_avatarPath != null)
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('恢复默认头像'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _clearAvatar();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsEntryTile(
      icon: Icons.badge_outlined,
      title: '设备身份',
      subtitle: _resolvedDisplayName,
      leading: UserAvatar(
        key: ValueKey(_avatarPath ?? 'no-avatar'),
        spec: selfAvatarSpec(
          customAvatarPath: _avatarPath,
          displayName: _resolvedDisplayName,
        ),
        size: 44,
      ),
      onTap: _showIdentityOptions,
    );
  }
}

class _EditDisplayAliasDialog extends StatefulWidget {
  const _EditDisplayAliasDialog({this.initialAlias});

  final String? initialAlias;

  @override
  State<_EditDisplayAliasDialog> createState() => _EditDisplayAliasDialogState();
}

class _EditDisplayAliasDialogState extends State<_EditDisplayAliasDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAlias ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置名称'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '例如：客厅平板',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SettingsEntryTile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsEntryTile({
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6E2DC)),
          ),
          child: Row(
            children: [
              leading ??
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3EC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: const Color(0xFF3D8A5A)),
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((subtitle?.trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6D6C6A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF6D6C6A)),
            ],
          ),
        ),
      ),
    );
  }
}
