import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/device/device_file_service.dart';

class BenchmarkFileGenerator {
  BenchmarkFileGenerator({required DeviceFileService deviceFileService})
    : _deviceFileService = deviceFileService;

  static const int _chunkSize = 256 * 1024;

  final DeviceFileService _deviceFileService;

  Future<GeneratedBenchmarkFile> generate({
    required int fileSizeBytes,
    required String fileName,
  }) async {
    final filePath = await createTemporaryPath(fileName: fileName);
    final stopwatch = Stopwatch()..start();
    final file = File(filePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final pattern = Uint8List(_chunkSize);
    for (var index = 0; index < pattern.length; index += 1) {
      pattern[index] = index % 251;
    }
    var writtenBytes = 0;
    try {
      while (writtenBytes < fileSizeBytes) {
        final remainingBytes = fileSizeBytes - writtenBytes;
        if (remainingBytes >= pattern.length) {
          sink.add(pattern);
          writtenBytes += pattern.length;
          continue;
        }
        sink.add(pattern.sublist(0, remainingBytes));
        writtenBytes += remainingBytes;
      }
    } finally {
      await sink.close();
    }
    stopwatch.stop();
    return GeneratedBenchmarkFile(
      filePath: filePath,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      generationMs: stopwatch.elapsedMilliseconds,
    );
  }

  Future<String> createTemporaryPath({required String fileName}) async {
    final cacheDir = await _deviceFileService.getAppCacheDirectory();
    final benchmarkDir = Directory(p.join(cacheDir, 'benchmark'));
    if (!await benchmarkDir.exists()) {
      await benchmarkDir.create(recursive: true);
    }
    return p.join(benchmarkDir.path, fileName);
  }
}

class GeneratedBenchmarkFile {
  const GeneratedBenchmarkFile({
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.generationMs,
  });

  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final int generationMs;
}
