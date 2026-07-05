/// 文件职责：实现服务器发现仓库具体业务逻辑
/// 文件对外接口：ServerDiscoveryRepositoryImpl
/// 文件包含：ServerDiscoveryRepositoryImpl
import 'dart:async';
import '../../../../core/node/unified_node.dart';
import '../../domain/repositories/server_discovery_repository.dart';
import '../datasources/mdns_discovery_data_source.dart';

class ServerDiscoveryRepositoryImpl implements ServerDiscoveryRepository {
  final MdnsDiscoveryDataSource _dataSource;

  ServerDiscoveryRepositoryImpl({required MdnsDiscoveryDataSource dataSource})
    : _dataSource = dataSource;

  @override
  Stream<List<UnifiedNode>> discoverServers() {
    return _dataSource.discoverServers();
  }

  @override
  void stopDiscovery() {
    _dataSource.stopDiscovery();
  }
}
