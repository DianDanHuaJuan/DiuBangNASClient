import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/dio_path_download_service.dart';

void main() {
  group('DioPathDownloadService', () {
    test('collects range download diagnostics for large files', () async {
      final payloadLength = 17 * 1024 * 1024;
      final payload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => index % 251),
      );
      final rangeHeaders = <String?>[];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        rangeHeaders.add(rangeHeader);

        if (rangeHeader == null) {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers
            ..set(HttpHeaders.contentLengthHeader, payload.length)
            ..set(HttpHeaders.acceptRangesHeader, 'bytes');
          await request.response.addStream(Stream<List<int>>.value(payload));
          await request.response.close();
          return;
        }

        final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(rangeHeader);
        expect(match, isNotNull);
        final start = int.parse(match!.group(1)!);
        final end = int.parse(match.group(2)!);
        final chunk = payload.sublist(start, end + 1);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers
          ..set(HttpHeaders.contentLengthHeader, chunk.length)
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${payload.length}',
          );
        await request.response.addStream(Stream<List<int>>.value(chunk));
        await request.response.close();
      });

      final service = DioPathDownloadService(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}')),
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'dio_path_download_service_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final savePath = '${tempDirectory.path}\\download.bin';

      final result = await service.downloadToPath(
        url: '/download',
        savePath: savePath,
        expectedSize: payload.length,
        supportsRange: true,
      );

      final downloadedBytes = await File(savePath).readAsBytes();
      expect(result.usedConcurrentRanges, isTrue);
      expect(downloadedBytes, payload);
      expect(result.diagnostics.rangeRequests.length, greaterThan(1));
      expect(result.diagnostics.flushCount, greaterThan(0));
      expect(result.diagnostics.localWriteMs, greaterThanOrEqualTo(0));
      expect(result.diagnostics.networkReceiveMs, greaterThanOrEqualTo(0));
      expect(
        result.diagnostics.configuredConcurrency,
        PathDownloadStrategy.defaultPreferredConcurrentRequests,
      );
      expect(result.diagnostics.effectiveConcurrency, greaterThanOrEqualTo(2));
      expect(
        rangeHeaders
            .whereType<String>()
            .where((value) => value.startsWith('bytes='))
            .length,
        result.diagnostics.rangeRequests.length,
      );
    });

    test('splits and requeues stalled ranges', () async {
      const chunkSize = 12 * 1024 * 1024;
      final payloadLength = 25 * 1024 * 1024;
      final payload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => index % 251),
      );
      final rangeAttempts = <String, int>{};

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        if (rangeHeader == null) {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers
            ..set(HttpHeaders.contentLengthHeader, payload.length)
            ..set(HttpHeaders.acceptRangesHeader, 'bytes');
          await request.response.addStream(Stream<List<int>>.value(payload));
          await request.response.close();
          return;
        }

        rangeAttempts.update(
          rangeHeader,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(rangeHeader);
        expect(match, isNotNull);
        final start = int.parse(match!.group(1)!);
        final end = int.parse(match.group(2)!);
        final chunk = payload.sublist(start, end + 1);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers
          ..set(HttpHeaders.contentLengthHeader, chunk.length)
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${payload.length}',
          );

        if (rangeHeader == 'bytes=0-${chunkSize - 1}' &&
            rangeAttempts[rangeHeader] == 1) {
          await request.response.addStream(
            Stream<List<int>>.value(chunk.sublist(0, 1024 * 1024)),
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          try {
            await request.response.addStream(
              Stream<List<int>>.value(chunk.sublist(1024 * 1024)),
            );
          } catch (_) {}
          await request.response.close();
          return;
        }

        await request.response.addStream(Stream<List<int>>.value(chunk));
        await request.response.close();
      });

      final service = DioPathDownloadService(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}')),
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'dio_path_download_service_stall_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final savePath = '${tempDirectory.path}\\download.bin';

      final result = await service.downloadToPath(
        url: '/download',
        savePath: savePath,
        expectedSize: payload.length,
        supportsRange: true,
        strategy: const PathDownloadStrategy(
          preferredConcurrentRequests: 2,
          initialChunkSizeBytes: chunkSize,
          minimumChunkSizeBytes: 4 * 1024 * 1024,
          stallTimeout: Duration(milliseconds: 100),
        ),
      );

      final downloadedBytes = await File(savePath).readAsBytes();
      expect(downloadedBytes, payload);
      expect(result.usedConcurrentRanges, isTrue);
      expect(result.diagnostics.slowRangeCount, 0);
      expect(result.diagnostics.stallCount, greaterThan(0));
      expect(result.diagnostics.splitCount, greaterThan(0));
      expect(result.diagnostics.requeueCount, greaterThan(0));
      expect(result.diagnostics.rangeRequests.length, greaterThan(3));
      expect(
        result.diagnostics.rangeRequests.any((request) => request.wasStalled),
        isTrue,
      );
    });

    test('detects slow ranges and steals tail work before timeout', () async {
      const chunkSize = 12 * 1024 * 1024;
      final payloadLength = 28 * 1024 * 1024;
      final payload = Uint8List.fromList(
        List<int>.generate(payloadLength, (index) => index % 251),
      );
      final rangeHeaders = <String>[];

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        if (rangeHeader == null) {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers
            ..set(HttpHeaders.contentLengthHeader, payload.length)
            ..set(HttpHeaders.acceptRangesHeader, 'bytes');
          await request.response.addStream(Stream<List<int>>.value(payload));
          await request.response.close();
          return;
        }

        rangeHeaders.add(rangeHeader);
        final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(rangeHeader);
        expect(match, isNotNull);
        final start = int.parse(match!.group(1)!);
        final end = int.parse(match.group(2)!);
        final chunk = payload.sublist(start, end + 1);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers
          ..set(HttpHeaders.contentLengthHeader, chunk.length)
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${payload.length}',
          );

        if (rangeHeader == 'bytes=0-${chunkSize - 1}') {
          const segmentBytes = 256 * 1024;
          for (var offset = 0; offset < chunk.length; offset += segmentBytes) {
            final segmentEnd = (offset + segmentBytes < chunk.length)
                ? offset + segmentBytes
                : chunk.length;
            try {
              await request.response.addStream(
                Stream<List<int>>.value(chunk.sublist(offset, segmentEnd)),
              );
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 60));
            } catch (_) {
              break;
            }
          }
          await request.response.close();
          return;
        }

        await request.response.addStream(Stream<List<int>>.value(chunk));
        await request.response.close();
      });

      final service = DioPathDownloadService(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}')),
      );
      final tempDirectory = await Directory.systemTemp.createTemp(
        'dio_path_download_service_slow_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final savePath = '${tempDirectory.path}\\download.bin';

      final result = await service.downloadToPath(
        url: '/download',
        savePath: savePath,
        expectedSize: payload.length,
        supportsRange: true,
        strategy: const PathDownloadStrategy(
          preferredConcurrentRequests: 2,
          initialChunkSizeBytes: chunkSize,
          minimumChunkSizeBytes: 4 * 1024 * 1024,
          stallTimeout: Duration(seconds: 2),
          slowRangeGracePeriod: Duration(milliseconds: 150),
          slowRangeMinimumBytes: 512 * 1024,
          slowRangeThroughputRatio: 0.5,
        ),
      );

      final downloadedBytes = await File(savePath).readAsBytes();
      expect(downloadedBytes, payload);
      expect(result.usedConcurrentRanges, isTrue);
      expect(result.diagnostics.slowRangeCount, greaterThan(0));
      expect(result.diagnostics.stallCount, 0);
      expect(result.diagnostics.splitCount, greaterThan(0));
      expect(result.diagnostics.requeueCount, greaterThan(0));
      expect(result.diagnostics.stealCount, greaterThan(0));
      expect(
        result.diagnostics.rangeRequests.any((request) => request.wasSlow),
        isTrue,
      );
      expect(
        rangeHeaders.where((header) => header.startsWith('bytes=0-')).length,
        1,
      );
      expect(
        rangeHeaders.any((header) {
          final match = RegExp(r'^bytes=(\d+)-').firstMatch(header);
          if (match == null) {
            return false;
          }
          final start = int.parse(match.group(1)!);
          return start > 0 && start < chunkSize;
        }),
        isTrue,
      );
    });
  });
}
