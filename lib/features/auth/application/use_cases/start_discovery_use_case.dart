/// 文件输入：无
/// 文件职责：执行 mDNS 扫描，返回发现的服务器列表流
/// 文件对外接口：StartDiscoveryUseCase
/// 文件包含：StartDiscoveryUseCase
import 'dart:async';
import '../../../../core/node/unified_node.dart';
import '../../domain/repositories/server_discovery_repository.dart';

class StartDiscoveryUseCase {
  final ServerDiscoveryRepository _repository;

  StartDiscoveryUseCase({required ServerDiscoveryRepository repository})
    : _repository = repository;

  Stream<List<UnifiedNode>> call() {
    return _repository.discoverServers();
  }
}
