import 'dart:typed_data';

import '../../../core/profile/device_avatar_processor.dart';
import '../../../core/device/client_identity_service.dart';
import '../../../core/node/device_alias_constraints.dart';
import '../../../core/node/device_display_resolver.dart';
import '../../../core/node/unified_node_store.dart';
import '../../../core/profile/device_identity_store.dart';
import '../data/device_profile_remote_data_source.dart';

typedef RealtimeHelloRefresher = Future<void> Function();

class DeviceIdentityService {
  DeviceIdentityService({
    required DeviceIdentityStore identityStore,
    required DeviceProfileRemoteDataSource remoteDataSource,
    required ClientIdentityService clientIdentityService,
    required UnifiedNodeStore unifiedNodeStore,
    RealtimeHelloRefresher? refreshRealtimeHello,
  }) : _identityStore = identityStore,
       _remoteDataSource = remoteDataSource,
       _clientIdentityService = clientIdentityService,
       _unifiedNodeStore = unifiedNodeStore,
       _refreshRealtimeHello = refreshRealtimeHello;

  final DeviceIdentityStore _identityStore;
  final DeviceProfileRemoteDataSource _remoteDataSource;
  final ClientIdentityService _clientIdentityService;
  final UnifiedNodeStore _unifiedNodeStore;
  RealtimeHelloRefresher? _refreshRealtimeHello;

  void bindRealtimeHelloRefresher(RealtimeHelloRefresher refresher) {
    _refreshRealtimeHello = refresher;
  }

  String? get localAlias => _identityStore.displayAlias;

  String? get localAvatarPath => _identityStore.avatarPath;

  DateTime? get avatarUpdatedAt => _identityStore.avatarUpdatedAt;

  Future<String> resolvePublicDisplayName() async {
    return DeviceDisplayResolver.localPublicDisplayName(
      alias: _identityStore.displayAlias,
      hardwareName: await _clientIdentityService.getDeviceName(),
    );
  }

  Future<String> resolvePresenceLabel() => resolvePublicDisplayName();

  Future<void> syncFromServer() async {
    try {
      final profile = await _remoteDataSource.fetchMyProfile();
      if (profile.label != null && profile.label!.trim().isNotEmpty) {
        await _identityStore.saveDisplayAlias(profile.label!);
      }
      if (profile.avatarUpdatedAt != null) {
        await _identityStore.markAvatarSynced(profile.avatarUpdatedAt!);
      }
      _applySelfNodeLabel(profile.label);
    } catch (_) {
      _applySelfNodeLabel(_identityStore.displayAlias);
    }
  }

  Future<void> updateDisplayAlias(String alias) async {
    final normalized = DeviceAliasConstraints.normalizeForSave(alias);
    final profile = await _remoteDataSource.updateLabel(normalized ?? '');
    if (normalized == null) {
      await _identityStore.clearDisplayAlias();
    } else {
      await _identityStore.saveDisplayAlias(normalized);
    }
    _applySelfNodeLabel(profile.label ?? normalized);
  }

  Future<void> setAvatarFromPath(String sourcePath) async {
    final bytes = await DeviceAvatarProcessor.prepareFromFile(sourcePath);
    await setAvatarFromBytes(bytes);
  }

  Future<void> setAvatarFromBytes(Uint8List bytes) async {
    final savedPath = await _identityStore.saveAvatarBytes(bytes);
    if (savedPath == null) {
      throw StateError('头像保存到本地失败');
    }
    try {
      final updatedAt = await _remoteDataSource.uploadAvatar(bytes);
      if (updatedAt != null) {
        await _identityStore.markAvatarSynced(updatedAt);
      }
    } catch (error) {
      throw StateError('头像上传失败：$error');
    }
    await _refreshRealtimeHello?.call();
  }

  Future<void> clearAvatar() async {
    await _identityStore.clearAvatar();
    try {
      await _remoteDataSource.deleteAvatar();
    } catch (_) {}
    await _refreshRealtimeHello?.call();
  }

  void _applySelfNodeLabel(String? label) {
    final sanitized = label?.trim();
    _unifiedNodeStore.applyLocalClientDisplayAlias(
      sanitized == null || sanitized.isEmpty ? null : sanitized,
    );
  }
}
