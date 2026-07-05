/// 文件职责：定义服务器发现仓库抽象接口
/// 文件对外接口：ServerDiscoveryRepository
/// 文件包含：ServerDiscoveryRepository
import 'dart:async';
import '../../../../core/node/unified_node.dart';

abstract class ServerDiscoveryRepository {
  Stream<List<UnifiedNode>> discoverServers();
  void stopDiscovery();
}
