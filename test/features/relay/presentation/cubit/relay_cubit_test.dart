import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/device_file_service.dart';
import 'package:nasclient/core/error/app_failure.dart';
import 'package:nasclient/core/node/realtime_presence_client_dto.dart';
import 'package:nasclient/core/node/unified_node_store.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/relay/domain/entities/relay_peer_history_page.dart';
import 'package:nasclient/features/relay/domain/entities/relay_transfer_entity.dart';
import 'package:nasclient/features/relay/domain/repositories/relay_repository.dart';
import 'package:nasclient/features/relay/presentation/cubit/relay_cubit.dart';

void main() {
  group('RelayCubit', () {
    test(
      'merges relay history with presence peers and filters current client',
      () async {
        final session = _buildSession();
        final repository = _FakeRelayRepository(
          historyResult: Success(<RelayTransferEntity>[
            _transfer(
              transferId: 'relay-1',
              senderClientId: 'phone-01',
              senderLabel: 'Phone 01',
              status: RelayTransferStatus.ready,
            ),
          ]),
        );
        final nodeStore = UnifiedNodeStore()..applyCurrentSession(session);
        final cubit = RelayCubit(
          relayRepository: repository,
          deviceFileService: _FakeDeviceFileService(),
          unifiedNodeStore: nodeStore,
        );
        addTearDown(cubit.close);

        await cubit.loadHistory();
        nodeStore.applyPresenceSnapshot(<RealtimePresenceClientDto>[
          RealtimePresenceClientDto.fromJson(
            _presencePeerJson(clientId: 'tablet-01', label: 'Self'),
          ),
          RealtimePresenceClientDto.fromJson(
            _presencePeerJson(clientId: 'phone-01', label: 'Phone 01'),
          ),
          RealtimePresenceClientDto.fromJson(
            _presencePeerJson(clientId: 'laptop-02', label: 'Laptop 02'),
          ),
        ]);

        expect(
          cubit.peers.map((peer) => peer.identity.clientId),
          containsAll(<String>['phone-01', 'laptop-02']),
        );
        expect(
          cubit.state.transfersForPeer('tablet-01', 'phone-01').single.fileName,
          'demo.txt',
        );
      },
    );

    test(
      'sendFilesToPeer reports partial failures and keeps successful transfers',
      () async {
        final session = _buildSession();
        final sentTransfer = _transfer(
          transferId: 'relay-1',
          senderClientId: 'tablet-01',
          senderLabel: 'Tablet 01',
          status: RelayTransferStatus.ready,
        );
        final repository = _FakeRelayRepository(
          historyResult: Success(<RelayTransferEntity>[sentTransfer]),
          sendResults: <AppResult<RelayTransferEntity>>[
            Success(sentTransfer),
            Failure(
              AppFailure.fromException(
                code: 'RELAY_SEND_FAILED',
                message: 'network error',
              ),
            ),
          ],
        );
        final nodeStore = UnifiedNodeStore()..applyCurrentSession(session);
        final cubit = RelayCubit(
          relayRepository: repository,
          deviceFileService: _FakeDeviceFileService(
            pickedFiles: <String>['C:\\temp\\a.txt', 'C:\\temp\\b.txt'],
          ),
          unifiedNodeStore: nodeStore,
        );
        addTearDown(cubit.close);

        await cubit.sendFilesToPeer('phone-01');

        expect(
          repository.sentRequests,
          <({String receiverClientId, String localPath})>[
            (receiverClientId: 'phone-01', localPath: 'C:\\temp\\a.txt'),
            (receiverClientId: 'phone-01', localPath: 'C:\\temp\\b.txt'),
          ],
        );
        expect(cubit.state.transfers, hasLength(1));
        expect(cubit.state.message, '已发送 1 个文件，1 个失败');
      },
    );

    test('applyTransferEvent increments unread for incoming transfer.ready', () {
      final session = _buildSession();
      final nodeStore = UnifiedNodeStore()..applyCurrentSession(session);
      final cubit = RelayCubit(
        relayRepository: _FakeRelayRepository(),
        deviceFileService: _FakeDeviceFileService(),
        unifiedNodeStore: nodeStore,
      );
      addTearDown(cubit.close);

      cubit.applyTransferEvent('transfer.ready', <String, dynamic>{
        'transfer': _transferJson(
          transferId: 'relay-in-1',
          senderClientId: 'phone-01',
          receiverClientId: 'tablet-01',
        ),
      });

      expect(cubit.state.unreadForPeer('phone-01'), 1);
      expect(cubit.state.totalUnread, 1);
    });

    test('loadPeerConversation stores ascending peer history page', () async {
      final session = _buildSession();
      final olderTransfer = _transfer(
        transferId: 'relay-old',
        senderClientId: 'phone-01',
        senderLabel: 'Phone 01',
        status: RelayTransferStatus.completed,
        createdAt: DateTime(2026, 4, 12, 9),
      );
      final newerTransfer = _transfer(
        transferId: 'relay-new',
        senderClientId: 'phone-01',
        senderLabel: 'Phone 01',
        status: RelayTransferStatus.ready,
        createdAt: DateTime(2026, 4, 12, 11),
      );
      final repository = _FakeRelayRepository(
        peerHistoryResult: Success(
          RelayPeerHistoryPage(
            transfers: <RelayTransferEntity>[olderTransfer, newerTransfer],
            hasMore: true,
          ),
        ),
      );
      final nodeStore = UnifiedNodeStore()..applyCurrentSession(session);
      final cubit = RelayCubit(
        relayRepository: repository,
        deviceFileService: _FakeDeviceFileService(),
        unifiedNodeStore: nodeStore,
      );
      addTearDown(cubit.close);

      await cubit.loadPeerConversation('phone-01');

      final history = cubit.state.peerHistory('phone-01');
      expect(history.transfers.map((transfer) => transfer.transferId), [
        'relay-old',
        'relay-new',
      ]);
      expect(history.hasMore, isTrue);
      expect(history.isLoadingInitial, isFalse);
    });

    test('loadOlderPeerMessages prepends older transfers for peer', () async {
      final session = _buildSession();
      final oldestTransfer = _transfer(
        transferId: 'relay-oldest',
        senderClientId: 'phone-01',
        senderLabel: 'Phone 01',
        status: RelayTransferStatus.completed,
        createdAt: DateTime(2026, 4, 12, 8),
      );
      final recentTransfer = _transfer(
        transferId: 'relay-recent',
        senderClientId: 'phone-01',
        senderLabel: 'Phone 01',
        status: RelayTransferStatus.ready,
        createdAt: DateTime(2026, 4, 12, 12),
      );
      final repository = _FakeRelayRepository(
        peerHistoryResults: <AppResult<RelayPeerHistoryPage>>[
          Success(
            RelayPeerHistoryPage(
              transfers: <RelayTransferEntity>[recentTransfer],
              hasMore: true,
            ),
          ),
          Success(
            RelayPeerHistoryPage(
              transfers: <RelayTransferEntity>[oldestTransfer],
              hasMore: false,
            ),
          ),
        ],
      );
      final nodeStore = UnifiedNodeStore()..applyCurrentSession(session);
      final cubit = RelayCubit(
        relayRepository: repository,
        deviceFileService: _FakeDeviceFileService(),
        unifiedNodeStore: nodeStore,
      );
      addTearDown(cubit.close);

      await cubit.loadPeerConversation('phone-01');
      await cubit.loadOlderPeerMessages('phone-01');

      final history = cubit.state.peerHistory('phone-01');
      expect(history.transfers.map((transfer) => transfer.transferId), [
        'relay-oldest',
        'relay-recent',
      ]);
      expect(history.hasMore, isFalse);
      expect(history.isLoadingMore, isFalse);
    });

    test(
      'applyTransferEvent updates empty active peer conversation',
      () async {
        final session = _buildSession();
        final repository = _FakeRelayRepository(
          peerHistoryResult: Success(
            RelayPeerHistoryPage(
              transfers: const <RelayTransferEntity>[],
              hasMore: false,
            ),
          ),
        );
        final nodeStore = UnifiedNodeStore()..applyCurrentSession(session);
        final cubit = RelayCubit(
          relayRepository: repository,
          deviceFileService: _FakeDeviceFileService(),
          unifiedNodeStore: nodeStore,
        );
        addTearDown(cubit.close);

        cubit.setActivePeer('phone-01');
        await cubit.loadPeerConversation('phone-01');
        expect(cubit.state.peerHistory('phone-01').transfers, isEmpty);

        cubit.applyTransferEvent('transfer.ready', <String, dynamic>{
          'transfer': _transferJson(
            transferId: 'relay-in-empty',
            senderClientId: 'phone-01',
            receiverClientId: 'tablet-01',
          ),
        });

        expect(cubit.state.peerHistory('phone-01').transfers, hasLength(1));
        expect(
          cubit.state.peerHistory('phone-01').transfers.single.transferId,
          'relay-in-empty',
        );
      },
    );

    test('markPeerRead clears unread count for peer', () async {
      final session = _buildSession();
      final nodeStore = UnifiedNodeStore()..applyCurrentSession(session);
      final cubit = RelayCubit(
        relayRepository: _FakeRelayRepository(),
        deviceFileService: _FakeDeviceFileService(),
        unifiedNodeStore: nodeStore,
      );
      addTearDown(cubit.close);

      cubit.applyTransferEvent('transfer.created', <String, dynamic>{
        'transfer': _transferJson(
          transferId: 'relay-in-2',
          senderClientId: 'phone-01',
          receiverClientId: 'tablet-01',
        ),
      });
      await cubit.markPeerRead('phone-01');

      expect(cubit.state.unreadForPeer('phone-01'), 0);
    });
  });
}

CurrentSession _buildSession() {
  final session = CurrentSession();
  session.clear();
  session.set(
    serverId: 'server-1',
    serverName: 'MiniNAS',
    serverVersion: '1.0.0',
    serverStatus: 'online',
    serverUrl: 'http://localhost:8080',
    username: 'client-user',
    password: '',
    protocol: 'webdav',
    rootId: 'fs',
    rootName: 'NAS',
    accountId: 'acct-1',
    role: 'client',
    clientId: 'tablet-01',
    sessionId: 'sess-1',
    accessToken: 'access-token-1',
    capabilities: const {
      'relay': {'enabled': false},
    },
  );
  return session;
}

RelayTransferEntity _transfer({
  required String transferId,
  required String senderClientId,
  required String senderLabel,
  required RelayTransferStatus status,
  DateTime? createdAt,
}) {
  final effectiveCreatedAt = createdAt ?? DateTime(2026, 4, 12, 10);
  return RelayTransferEntity(
    transferId: transferId,
    senderAccountId: 'acct-1',
    senderLabel: senderLabel,
    senderClientId: senderClientId,
    targetCount: 1,
    fileName: 'demo.txt',
    fileSize: 128,
    checksumAlgorithm: 'sha256',
    chunkSize: 1048576,
    storageMode: 'store_on_nas',
    status: status,
    createdAt: effectiveCreatedAt,
    updatedAt: effectiveCreatedAt.add(const Duration(minutes: 1)),
    expiresAt: effectiveCreatedAt.add(const Duration(days: 3)),
    targets: <RelayTransferTargetEntity>[
      RelayTransferTargetEntity(
        transferId: transferId,
        receiverClientId: 'tablet-01',
        deliveryState: RelayTransferTargetState.ready,
        updatedAt: DateTime(2026, 4, 12, 10, 1),
      ),
    ],
    artifact: RelayTransferArtifactEntity(
      transferId: transferId,
      tempPath: 'D:\\relay\\$transferId.part',
      chunkCount: 1,
      receivedBytes: 128,
      isSealed: true,
      cleanupState: RelayArtifactCleanupState.sealed,
      updatedAt: DateTime(2026, 4, 12, 10, 1),
    ),
  );
}

Map<String, dynamic> _presencePeerJson({
  required String clientId,
  required String label,
}) {
  return <String, dynamic>{
    'connectionId': 'conn-$clientId',
    'sessionId': 'sess-$clientId',
    'accountId': 'acct-$clientId',
    'role': 'client',
    'clientId': clientId,
    'label': label,
    'deviceName': label,
    'status': 'online',
    'connectedAt': '2026-04-12T10:00:00.000Z',
    'lastSeenAt': '2026-04-12T10:05:00.000Z',
  };
}

Map<String, dynamic> _transferJson({
  required String transferId,
  required String senderClientId,
  required String receiverClientId,
}) {
  return <String, dynamic>{
    'transferId': transferId,
    'senderAccountId': 'acct-1',
    'senderLabel': senderClientId,
    'senderClientId': senderClientId,
    'targetCount': 1,
    'fileName': 'demo.txt',
    'fileSize': 128,
    'checksumAlgorithm': 'sha256',
    'chunkSize': 1048576,
    'storageMode': 'store_on_nas',
    'status': 'ready',
    'createdAt': '2026-04-12T10:00:00.000Z',
    'updatedAt': '2026-04-12T10:01:00.000Z',
    'expiresAt': '2026-04-15T10:00:00.000Z',
    'targets': <Map<String, dynamic>>[
      <String, dynamic>{
        'transferId': transferId,
        'receiverClientId': receiverClientId,
        'deliveryState': 'ready',
        'updatedAt': '2026-04-12T10:01:00.000Z',
      },
    ],
    'artifact': <String, dynamic>{
      'transferId': transferId,
      'tempPath': 'D:\\relay\\$transferId.part',
      'chunkCount': 1,
      'receivedBytes': 128,
      'isSealed': true,
      'cleanupState': 'sealed',
      'updatedAt': '2026-04-12T10:01:00.000Z',
    },
    'transport': <String, dynamic>{
      'protocol': 'webdav',
      'upload': <String, dynamic>{
        'method': 'PUT',
        'path': '/dav/relay/$transferId/payload',
      },
      'download': <String, dynamic>{
        'method': 'GET',
        'path': '/dav/relay/$transferId/payload',
        'supportsRange': true,
      },
    },
  };
}

class _FakeRelayRepository implements RelayRepository {
  AppResult<List<RelayTransferEntity>> historyResult;
  AppResult<RelayPeerHistoryPage> peerHistoryResult;
  final List<AppResult<RelayPeerHistoryPage>> peerHistoryResults;
  final List<AppResult<RelayTransferEntity>> sendResults;
  final List<({String receiverClientId, String localPath})> sentRequests =
      <({String receiverClientId, String localPath})>[];
  int _peerHistoryRequestCount = 0;

  _FakeRelayRepository({
    this.historyResult = const Success(<RelayTransferEntity>[]),
    AppResult<RelayPeerHistoryPage>? peerHistoryResult,
    this.peerHistoryResults = const <AppResult<RelayPeerHistoryPage>>[],
    this.sendResults = const <AppResult<RelayTransferEntity>>[],
  }) : peerHistoryResult =
           peerHistoryResult ??
           const Success(
             RelayPeerHistoryPage(
               transfers: <RelayTransferEntity>[],
               hasMore: false,
             ),
           );

  @override
  Future<AppResult<RelayTransferEntity>> cancelTransfer({
    required String transferId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<RelayDownloadResult>> downloadTransfer({
    required RelayTransferEntity transfer,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<RelayTransferEntity>>> loadHistory() async {
    return historyResult;
  }

  @override
  Future<AppResult<RelayPeerHistoryPage>> loadPeerHistory({
    required String peerClientId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    if (peerHistoryResults.isEmpty) {
      return peerHistoryResult;
    }
    final index = _peerHistoryRequestCount;
    _peerHistoryRequestCount += 1;
    if (index >= peerHistoryResults.length) {
      return peerHistoryResults.last;
    }
    return peerHistoryResults[index];
  }

  @override
  Future<AppResult<String?>> downloadThumbnail({
    required String thumbnailPath,
    required String savePath,
  }) async {
    return const Success(null);
  }

  @override
  Future<AppResult<String?>> downloadThumbnailForTransfer({
    required RelayTransferEntity transfer,
    required String savePath,
  }) async {
    return const Success(null);
  }

  @override
  Future<AppResult<RelayTransferEntity>> retryTransfer({
    required String transferId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<RelayTransferEntity>> sendFile({
    required String receiverClientId,
    required String localPath,
    String? mimeType,
    void Function(RelayTransferEntity transfer)? onTransferCreated,
    void Function(RelayTransferEntity transfer, int sentBytes, int totalBytes)?
        onUploadProgress,
  }) async {
    sentRequests.add((
      receiverClientId: receiverClientId,
      localPath: localPath,
    ));
    if (sendResults.isEmpty) {
      throw StateError('sendResults must be configured');
    }
    return sendResults[sentRequests.length - 1];
  }
}

class _FakeDeviceFileService extends DeviceFileService {
  final List<String>? pickedFiles;

  _FakeDeviceFileService({this.pickedFiles});

  @override
  Future<List<String>?> pickMultipleFiles() async {
    return pickedFiles;
  }
}
