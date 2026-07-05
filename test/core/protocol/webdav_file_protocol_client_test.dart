import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/auth_headers.dart';
import 'package:nasclient/core/network/dio_path_download_service.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/core/protocol/webdav_file_protocol_client.dart';

void main() {
  group('WebdavFileProtocolClient', () {
    test(
      'adds bearer auth and client identity headers to WebDAV requests',
      () async {
        final dio = Dio();
        final client = WebdavFileProtocolClient(
          baseUrl: 'http://localhost:8080',
          authHeader: 'Bearer access-token-1',
          clientIdProvider: () async => 'android-device-01',
          clientNameProvider: () async => 'Xiaomi Pad 6',
          dio: dio,
        );
        late RequestOptions capturedRequest;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequest = options;
              handler.resolve(
                Response(requestOptions: options, statusCode: 200),
              );
            },
          ),
        );

        final exists = await client.exists(
          const NasPath(rootId: 'fs', path: '/docs/readme.txt'),
        );

        expect(exists, isTrue);
        expect(
          capturedRequest.headers['Authorization'],
          'Bearer access-token-1',
        );
        expect(
          capturedRequest.headers[clientIdHeaderName],
          'android-device-01',
        );
        expect(capturedRequest.headers[clientNameHeaderName], 'Xiaomi Pad 6');
      },
    );

    test('percent-encodes path segments containing literal percent signs', () async {
      final dio = Dio();
      final client = WebdavFileProtocolClient(
        baseUrl: 'http://localhost:8080',
        authHeader: 'Bearer access-token-1',
        dio: dio,
      );
      late RequestOptions capturedRequest;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response(requestOptions: options, statusCode: 200),
            );
          },
        ),
      );

      final exists = await client.exists(
        const NasPath(rootId: 'fs', path: '/100%完成.mht'),
      );

      expect(exists, isTrue);
      expect(capturedRequest.uri.path, '/dav/fs/100%25%E5%AE%8C%E6%88%90.mht');
    });

    test('preserves explicit port when building WebDAV URLs', () async {
      final dio = Dio();
      final client = WebdavFileProtocolClient(
        baseUrl: 'http://192.168.1.10:8080',
        authHeader: 'Bearer access-token-1',
        dio: dio,
      );
      late RequestOptions capturedRequest;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response(requestOptions: options, statusCode: 200),
            );
          },
        ),
      );

      final exists = await client.exists(
        const NasPath(rootId: 'fs', path: '/docs/readme.txt'),
      );

      expect(exists, isTrue);
      expect(capturedRequest.uri.host, '192.168.1.10');
      expect(capturedRequest.uri.port, 8080);
      expect(capturedRequest.uri.path, '/dav/fs/docs/readme.txt');
    });

    test('builds root directory WebDAV URL without throwing', () async {
      final dio = Dio();
      final client = WebdavFileProtocolClient(
        baseUrl: 'http://localhost:8080',
        authHeader: 'Bearer access-token-1',
        dio: dio,
      );
      late RequestOptions capturedRequest;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 207,
                data: _emptyPropfindResponse,
              ),
            );
          },
        ),
      );

      final entries = await client.listDirectory(
        const NasPath(rootId: 'fs', path: '/'),
      );

      expect(entries, isEmpty);
      expect(capturedRequest.uri.path, '/dav/fs');
    });

    test('uses the tuned direct download range preset', () async {
      final payloadLength =
          PathDownloadStrategy.defaultInitialChunkSizeBytes * 4 + 1024;
      final rangeHeaders = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        if (request.method == 'HEAD') {
          request.response.headers
            ..set(HttpHeaders.contentLengthHeader, payloadLength)
            ..set(HttpHeaders.acceptRangesHeader, 'bytes');
          await request.response.close();
          return;
        }

        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        expect(rangeHeader, isNotNull);
        rangeHeaders.add(rangeHeader!);
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

      final client = WebdavFileProtocolClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        authHeader: 'Bearer access-token-1',
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'webdav_direct_download_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final savePath = '${tempDirectory.path}\\direct.bin';

      final usedConcurrentRanges = await client.downloadToPath(
        sourcePath: const NasPath(rootId: 'fs', path: '/docs/direct.bin'),
        savePath: savePath,
        expectedSize: payloadLength,
      );

      final directChunkSize =
          PathDownloadStrategy.directDownloadDefault.initialChunkSizeBytes;
      expect(usedConcurrentRanges, isTrue);
      expect(await File(savePath).length(), payloadLength);
      expect(rangeHeaders, contains('bytes=0-${directChunkSize - 1}'));
      expect(
        rangeHeaders,
        isNot(contains('bytes=0-${(32 * 1024 * 1024) - 1}')),
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

const _emptyPropfindResponse =
    '<?xml version="1.0"?><multistatus xmlns="DAV:"></multistatus>';
