/// 文件输入：无
/// 文件职责：停止 mDNS 扫描
/// 文件对外接口：StopDiscoveryUseCase
/// 文件包含：StopDiscoveryUseCase
import '../../domain/repositories/server_discovery_repository.dart';

class StopDiscoveryUseCase {
  final ServerDiscoveryRepository _repository;

  StopDiscoveryUseCase({required ServerDiscoveryRepository repository})
    : _repository = repository;

  void call() {
    _repository.stopDiscovery();
  }
}
