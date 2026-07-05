import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/unified_node.dart';
import 'package:nasclient/core/node/unified_node_store.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/features/auth/domain/repositories/server_discovery_repository.dart';
import 'package:nasclient/features/auth/presentation/cubit/server_selection_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ServerSelectionCubit', () {
    test('times out after fixed duration and emits not-found notice', () async {
      final repository = _FakeServerDiscoveryRepository();
      final cubit = ServerSelectionCubit(
        discoveryRepository: repository,
        keyValueStore: await _buildKeyValueStore(),
        unifiedNodeStore: UnifiedNodeStore(),
        scanDuration: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        await cubit.close();
        await repository.dispose();
      });

      await cubit.startScan();

      expect(cubit.state.isScanning, isTrue);
      expect(cubit.state.discoveredServers, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(cubit.state.isScanning, isFalse);
      expect(cubit.state.hasCompletedScan, isTrue);
      expect(cubit.state.scanNoticeMessage, '未发现任何服务器');
      expect(cubit.state.scanNoticeVersion, 1);
      expect(repository.discoverCallCount, 1);
      expect(repository.stopCallCount, 1);
    });

    test(
      'keeps scanning during discovery and finishes without notice',
      () async {
        final repository = _FakeServerDiscoveryRepository();
        final cubit = ServerSelectionCubit(
          discoveryRepository: repository,
          keyValueStore: await _buildKeyValueStore(),
          unifiedNodeStore: UnifiedNodeStore(),
          scanDuration: const Duration(milliseconds: 20),
        );
        addTearDown(() async {
          await cubit.close();
          await repository.dispose();
        });

        await cubit.loadSavedServers();
        await cubit.startScan();
        repository.emit([
          UnifiedNode.discoveredServer(
            name: 'MiniNAS',
            host: '192.168.1.10',
            port: 8080,
            serviceType: '_webdav._tcp.',
          ),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(cubit.state.isScanning, isTrue);
        expect(cubit.state.discoveredServers, hasLength(1));

        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(cubit.state.isScanning, isFalse);
        expect(cubit.state.hasCompletedScan, isTrue);
        expect(cubit.state.scanNoticeMessage, isNull);
        expect(repository.stopCallCount, 1);
      },
    );

    test(
      'rescanning reprobes saved servers and refreshes stale offline state',
      () async {
        const savedUrl = 'https://192.168.1.10:8080';
        final repository = _FakeServerDiscoveryRepository();
        final probe = _SequencedOnlineProbe({
          savedUrl: [false, true],
        });
        final cubit = ServerSelectionCubit(
          discoveryRepository: repository,
          keyValueStore: await _buildKeyValueStore(
            initialValues: <String, Object>{
              'server_list': jsonEncode([
                UnifiedNode.savedServer(
                  serverUrl: savedUrl,
                  displayName: 'MiniNAS',
                  updatedAt: DateTime.utc(2026, 5, 17, 10),
                ).toSavedServerJson(),
              ]),
            },
          ),
          unifiedNodeStore: UnifiedNodeStore(),
          scanDuration: const Duration(milliseconds: 20),
          onlineProbe: probe.call,
        );
        addTearDown(() async {
          await cubit.close();
          await repository.dispose();
        });

        await cubit.loadSavedServers();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(cubit.state.serverOnlineStatus[savedUrl], isFalse);

        await cubit.startScan();
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(cubit.state.serverOnlineStatus[savedUrl], isTrue);
        expect(repository.discoverCallCount, 1);
      },
    );

    test('stops discovery immediately when cubit closes', () async {
      final repository = _FakeServerDiscoveryRepository();
      final cubit = ServerSelectionCubit(
        discoveryRepository: repository,
        keyValueStore: await _buildKeyValueStore(),
        unifiedNodeStore: UnifiedNodeStore(),
        scanDuration: const Duration(seconds: 1),
      );
      addTearDown(repository.dispose);

      await cubit.startScan();
      expect(cubit.state.isScanning, isTrue);

      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repository.stopCallCount, 1);
    });
  });
}

Future<KeyValueStore> _buildKeyValueStore({
  Map<String, Object> initialValues = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  return KeyValueStore(prefs: prefs);
}

class _FakeServerDiscoveryRepository implements ServerDiscoveryRepository {
  final _controller = StreamController<List<UnifiedNode>>.broadcast();
  int discoverCallCount = 0;
  int stopCallCount = 0;

  @override
  Stream<List<UnifiedNode>> discoverServers() {
    discoverCallCount += 1;
    return _controller.stream;
  }

  @override
  void stopDiscovery() {
    stopCallCount += 1;
  }

  void emit(List<UnifiedNode> servers) {
    _controller.add(servers);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

class _SequencedOnlineProbe {
  _SequencedOnlineProbe(this._responses);

  final Map<String, List<bool>> _responses;

  Future<bool> call(String url) async {
    final values = _responses[url];
    if (values == null || values.isEmpty) {
      return false;
    }
    return values.removeAt(0);
  }
}
