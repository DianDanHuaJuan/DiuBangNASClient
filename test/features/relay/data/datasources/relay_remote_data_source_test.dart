import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/relay/data/datasources/relay_remote_data_source.dart';
import 'package:nasclient/features/relay/domain/entities/relay_transfer_entity.dart';

void main() {
  group('RelayRemoteDataSource', () {
    test(
      'createTransfer returns relay transport descriptors from server response',
      () async {
        final session = _buildSession();
        final dio = Dio();
        late RequestOptions capturedRequest;
        final client = NasApiClient(
          baseUrl: 'http://localhost:8080',
          session: session,
          clientIdProvider: () async => 'tablet-01',
          clientNameProvider: () async => 'Pixel 7',
          dio: dio,
        );
        final dataSource = RelayRemoteDataSource(apiClient: client);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequest = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 201,
                  data: <String, dynamic>{
                    'transfer': _relayTransferJson(status: 'created'),
                  },
                ),
              );
            },
          ),
        );

        final transfer = await dataSource.createTransfer(
          targetClientIds: const <String>['tablet-01'],
          fileName: 'demo.txt',
          fileSize: 128,
        );

        expect(capturedRequest.method, 'POST');
        expect(
          capturedRequest.path,
          '/api/v1/relay/transfers',
        );
        expect(
          capturedRequest.headers['Authorization'],
          'Bearer access-token-1',
        );
        expect(
          capturedRequest.data,
          <String, dynamic>{
            'targetClientIds': const <String>['tablet-01'],
            'fileName': 'demo.txt',
            'fileSize': 128,
          },
        );
        expect(transfer.status, RelayTransferStatus.created);
        expect(transfer.artifact.receivedBytes, 128);
        expect(transfer.transport?.protocol, 'webdav');
        expect(transfer.transport?.upload.path, '/dav/relay/relay-1/payload');
        expect(transfer.transport?.download.supportsRange, isTrue);
      },
    );

    test(
      'loadHistory parses transfer aggregates from server history',
      () async {
        final session = _buildSession();
        final dio = Dio();
        final client = NasApiClient(
          baseUrl: 'http://localhost:8080',
          session: session,
          dio: dio,
        );
        final dataSource = RelayRemoteDataSource(apiClient: client);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'transfers': <Map<String, dynamic>>[
                      _relayTransferJson(status: 'ready'),
                      _relayTransferJson(
                        transferId: 'relay-2',
                        senderClientId: 'laptop-02',
                        senderLabel: 'Laptop 02',
                        status: 'completed',
                      ),
                    ],
                  },
                ),
              );
            },
          ),
        );

        final transfers = await dataSource.loadHistory();

        expect(transfers, hasLength(2));
        expect(transfers.first.fileName, 'demo.txt');
        expect(transfers.last.status, RelayTransferStatus.completed);
        expect(transfers.last.targets.single.receiverClientId, 'tablet-01');
      },
    );

    test(
      'loadHistory tolerates purged transfers with empty tempPath',
      () async {
        final session = _buildSession();
        final dio = Dio();
        final client = NasApiClient(
          baseUrl: 'http://localhost:8080',
          session: session,
          dio: dio,
        );
        final dataSource = RelayRemoteDataSource(apiClient: client);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'transfers': <Map<String, dynamic>>[
                      _relayTransferJson(status: 'ready'),
                      _relayTransferJson(
                        transferId: 'relay-purged',
                        status: 'completed',
                        tempPath: '',
                        cleanupState: 'deleted',
                      ),
                    ],
                  },
                ),
              );
            },
          ),
        );

        final transfers = await dataSource.loadHistory();

        expect(transfers, hasLength(2));
        expect(transfers.last.artifact.cleanupState,
            RelayArtifactCleanupState.deleted);
        expect(transfers.last.artifact.tempPath, '/purged/relay-purged');
      },
    );

    test(
      'loadPeerHistory sends peer pagination query parameters',
      () async {
        final session = _buildSession();
        final dio = Dio();
        late RequestOptions capturedRequest;
        final client = NasApiClient(
          baseUrl: 'http://localhost:8080',
          session: session,
          dio: dio,
        );
        final dataSource = RelayRemoteDataSource(apiClient: client);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequest = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'transfers': <Map<String, dynamic>>[
                      _relayTransferJson(status: 'ready'),
                    ],
                    'hasMore': true,
                  },
                ),
              );
            },
          ),
        );

        final before = DateTime.utc(2026, 4, 12, 9);
        final page = await dataSource.loadPeerHistory(
          peerClientId: 'phone-01',
          limit: 20,
          beforeCreatedAt: before,
        );

        expect(capturedRequest.path, '/api/v1/relay/transfers/history');
        expect(
          capturedRequest.queryParameters,
          <String, dynamic>{
            'peerClientId': 'phone-01',
            'limit': 20,
            'before': before.toIso8601String(),
          },
        );
        expect(page.transfers, hasLength(1));
        expect(page.hasMore, isTrue);
      },
    );

    test(
      'acknowledgeDownloadCompleted posts relay completion ack',
      () async {
        final session = _buildSession();
        final dio = Dio();
        late RequestOptions capturedRequest;
        final client = NasApiClient(
          baseUrl: 'http://localhost:8080',
          session: session,
          dio: dio,
        );
        final dataSource = RelayRemoteDataSource(apiClient: client);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequest = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'transfer': _relayTransferJson(status: 'completed'),
                  },
                ),
              );
            },
          ),
        );

        final transfer = await dataSource.acknowledgeDownloadCompleted(
          transferId: 'relay-1',
        );

        expect(capturedRequest.method, 'POST');
        expect(
          capturedRequest.path,
          '/api/v1/relay/transfers/relay-1/download-complete',
        );
        expect(capturedRequest.data, <String, dynamic>{});
        expect(transfer.status, RelayTransferStatus.completed);
      },
    );
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
    roots: const [
      RootInfo(
        id: 'fs',
        name: 'NAS',
        path: '/fs',
        type: 'local',
        writable: true,
      ),
    ],
  );
  return session;
}

Map<String, dynamic> _relayTransferJson({
  String transferId = 'relay-1',
  String senderClientId = 'phone-01',
  String senderLabel = 'Phone 01',
  String status = 'ready',
  Object? tempPath,
  String cleanupState = '',
}) {
  final resolvedTempPath = switch (tempPath) {
    null => 'D:\\relay\\$transferId.part',
    final String value => value,
    _ => 'D:\\relay\\$transferId.part',
  };
  final resolvedCleanupState = cleanupState.isNotEmpty
      ? cleanupState
      : (status == 'uploading' ? 'pending' : 'sealed');
  return <String, dynamic>{
    'transferId': transferId,
    'senderAccountId': 'acct-1',
    'senderLabel': senderLabel,
    'senderClientId': senderClientId,
    'targetCount': 1,
    'fileName': 'demo.txt',
    'fileSize': 128,
    'checksumAlgorithm': 'sha256',
    'chunkSize': 1048576,
    'storageMode': 'store_on_nas',
    'status': status,
    'createdAt': '2026-04-12T10:00:00.000Z',
    'updatedAt': '2026-04-12T10:01:00.000Z',
    'expiresAt': '2026-04-15T10:00:00.000Z',
    'targets': [
      {
        'transferId': transferId,
        'receiverClientId': 'tablet-01',
        'deliveryState': status == 'completed' ? 'completed' : 'ready',
        'updatedAt': '2026-04-12T10:01:00.000Z',
      },
    ],
    'artifact': {
      'transferId': transferId,
      'tempPath': resolvedTempPath,
      'chunkCount': 1,
      'receivedBytes': 128,
      'isSealed': status != 'uploading',
      'cleanupState': resolvedCleanupState,
      'updatedAt': '2026-04-12T10:01:00.000Z',
    },
    'transport': {
      'protocol': 'webdav',
      'upload': {'method': 'PUT', 'path': '/dav/relay/$transferId/payload'},
      'download': {
        'method': 'GET',
        'path': '/dav/relay/$transferId/payload',
        'supportsRange': true,
      },
    },
  };
}
