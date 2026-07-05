import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/dio_path_download_service.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/relay/data/datasources/relay_webdav_transport_client.dart';

void main() {
  group('RelayWebdavTransportClient', () {
    test('downloads large relay files with concurrent range requests', () async {
      final payloadLength =
          PathDownloadStrategy.relayDownloadDefault.initialChunkSizeBytes * 4 +
          1024;
      final rangeHeaders = <String?>[];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        rangeHeaders.add(rangeHeader);

        if (rangeHeader == null) {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers
            ..set(HttpHeaders.contentLengthHeader, payloadLength)
            ..set(HttpHeaders.acceptRangesHeader, 'bytes');
          await request.response.addStream(_zeroByteStream(payloadLength));
          await request.response.close();
          return;
        }

        final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(rangeHeader);
        expect(match, isNotNull);
        final start = int.parse(match!.group(1)!);
        final end = int.parse(match.group(2)!);
        final chunkLength = end - start + 1;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers
          ..set(HttpHeaders.contentLengthHeader, chunkLength)
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$payloadLength',
          );
        await request.response.addStream(_zeroByteStream(chunkLength));
        await request.response.close();
      });

      final session = _buildSession(server.port);
      final client = RelayWebdavTransportClient(
        apiClient: NasApiClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          session: session,
        ),
      );

      final tempDirectory = await Directory.systemTemp.createTemp(
        'relay_range_client_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final savePath = '${tempDirectory.path}\\relay.bin';

      final result = await client.downloadToPath(
        relayPath: '/dav/relay/relay-1/payload',
        savePath: savePath,
        expectedSize: payloadLength,
        supportsRange: true,
      );

      expect(result.usedConcurrentRanges, isTrue);
      expect(result.diagnostics.rangeRequests.length, greaterThan(1));
      expect(result.diagnostics.flushCount, greaterThan(0));
      expect(await File(savePath).length(), payloadLength);
      expect(
        result.diagnostics.initialChunkSizeBytes,
        PathDownloadStrategy.relayDownloadDefault.initialChunkSizeBytes,
      );
      expect(rangeHeaders.whereType<String>().length, greaterThan(1));
      expect(
        rangeHeaders.whereType<String>().every(
          (value) => value.startsWith('bytes='),
        ),
        isTrue,
      );
      expect(
        rangeHeaders,
        contains(
          'bytes=0-${PathDownloadStrategy.relayDownloadDefault.initialChunkSizeBytes - 1}',
        ),
      );
    });
  });
}

Stream<List<int>> _zeroByteStream(int length) async* {
  var remaining = length;
  while (remaining > 0) {
    final chunkLength = remaining < 64 * 1024 ? remaining : 64 * 1024;
    yield List<int>.filled(chunkLength, 0, growable: false);
    remaining -= chunkLength;
  }
}

CurrentSession _buildSession(int port) {
  final session = CurrentSession();
  session.clear();
  session.set(
    serverId: 'server-1',
    serverName: 'MiniNAS',
    serverVersion: '1.0.0',
    serverStatus: 'online',
    serverUrl: 'http://127.0.0.1:$port',
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
