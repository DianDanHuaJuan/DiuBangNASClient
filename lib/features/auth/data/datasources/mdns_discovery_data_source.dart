/// 文件输入：NSD 服务
/// 文件职责：执行 NSD 局域网扫描，发现 NAS 服务器
/// 文件对外接口：MdnsDiscoveryDataSource
/// 文件包含：MdnsDiscoveryDataSource
import 'dart:async';
import 'package:flutter/services.dart';
import '../../../../core/node/unified_node.dart';

class MdnsDiscoveryDataSource {
  static const _methodChannel = MethodChannel('com.nasclient/nsd');
  static const _eventChannel = EventChannel('com.nasclient/nsd/events');
  StreamSubscription? _eventSubscription;
  StreamController<List<UnifiedNode>>? _controller;
  bool _isRunning = false;

  static const List<String> serviceTypes = ['_webdavs._tcp.'];

  Stream<List<UnifiedNode>> discoverServers() async* {
    if (_isRunning) return;
    _isRunning = true;

    final serversByServiceName = <String, UnifiedNode>{};
    _controller = StreamController<List<UnifiedNode>>.broadcast();

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final method = event['method'] as String?;
          if (method == 'onServiceFound') {
            final name = event['name'] as String?;
            final host = event['host'] as String?;
            final port = event['port'] as int?;
            final serviceType = event['serviceType'] as String?;
            final txtRecords = _parseTxtRecords(event['txtRecords']);

            if (name != null && host != null && port != null) {
              final server = UnifiedNode.discoveredServer(
                name: name,
                host: host,
                port: port,
                serviceType: serviceType ?? 'unknown',
                serverId: txtRecords['serverId'],
                caSha256: txtRecords['caSha256'],
                scheme: txtRecords['scheme'],
                baseUrl: txtRecords['baseUrl'],
                hostLabel: txtRecords['hostLabel'],
                platform: txtRecords['platform'],
              );
              serversByServiceName[name] = server;
              _controller?.add(List<UnifiedNode>.from(serversByServiceName.values));
            }
          } else if (method == 'onServiceLost') {
            final name = event['name'] as String?;
            if (name != null && serversByServiceName.remove(name) != null) {
              _controller?.add(List<UnifiedNode>.from(serversByServiceName.values));
            }
          } else {
            _controller?.add(List<UnifiedNode>.from(serversByServiceName.values));
          }
        }
      },
      onError: (error) {
        _controller?.addError(error);
      },
    );

    try {
      await _methodChannel.invokeMethod('startDiscovery', {
        'serviceTypes': serviceTypes,
      });

      yield* _controller!.stream;
    } catch (e) {
      yield List<UnifiedNode>.from(serversByServiceName.values);
    } finally {
      _isRunning = false;
    }
  }

  void stopDiscovery() {
    _isRunning = false;
    _eventSubscription?.cancel();
    _controller?.close();
    _methodChannel.invokeMethod('stopDiscovery');
  }

  Map<String, String> _parseTxtRecords(dynamic rawValue) {
    if (rawValue is! Map) {
      return const <String, String>{};
    }
    return rawValue.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }
}
