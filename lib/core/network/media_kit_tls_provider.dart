/// 文件输入：TrustedServerStore
/// 文件职责：为 media_kit Player 配置自签名 HTTPS TLS 信任
/// 文件对外接口：MediaKitTlsProvider
/// 文件包含：MediaKitTlsProvider
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'trusted_server_store.dart';

/// 为 [Player] 配置与当前 HTTPS 信任体系兼容的 TLS。
///
/// 复用 [TrustedServerStore] 中配对时安全获取的 rootCaPem，写入临时 CA
/// 文件后通过 libmpv 的 tls-ca-file + tls-verify 属性实现证书验证。
/// 与原 fork 的 TrustedServerRegistry 行为一致：验证 CA 证书链 + 主机名。
class MediaKitTlsProvider {
  MediaKitTlsProvider({required TrustedServerStore trustedServerStore})
    : _trustedServerStore = trustedServerStore;

  final TrustedServerStore _trustedServerStore;

  /// 为 [player] 配置 TLS 信任。
  ///
  /// 从 [TrustedServerStore] 查找匹配 [url] 的 rootCaPem，写入临时 CA
  /// 文件，通过 libmpv 属性实现证书验证。
  ///
  /// 返回 `true` 表示已配置 TLS；`false` 表示无信任记录（本地文件无需
  /// TLS，或尚未完成配对）。
  Future<bool> configurePlayer(Player player, String url) async {
    final record = _trustedServerStore.findByServerUrl(url);
    if (record == null) return false;

    final caPath = await _ensureCaFile(record);
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('tls-ca-file', caPath);
      await platform.setProperty('tls-verify', 'yes');
    }
    return true;
  }

  /// 将 rootCaPem 写入临时 CA 文件（内容变化时更新）。
  Future<String> _ensureCaFile(TrustedServerRecord record) async {
    final dir = await getTemporaryDirectory();
    final caFile = File('${dir.path}/nas_ca_${record.serverId}.pem');
    if (!caFile.existsSync() ||
        caFile.readAsStringSync() != record.rootCaPem) {
      await caFile.writeAsString(record.rootCaPem);
    }
    return caFile.path;
  }
}
