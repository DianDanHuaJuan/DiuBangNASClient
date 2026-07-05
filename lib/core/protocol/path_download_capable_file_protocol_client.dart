import '../path/nas_path.dart';

abstract interface class PathDownloadCapableFileProtocolClient {
  Future<bool> downloadToPath({
    required NasPath sourcePath,
    required String savePath,
    required int expectedSize,
    void Function(int received)? onProgress,
    bool Function()? shouldCancel,
  });
}

class PathDownloadCancelledException implements Exception {
  const PathDownloadCancelledException();
}
