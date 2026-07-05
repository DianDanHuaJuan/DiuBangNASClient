import 'dart:async';

import '../network/buffered_byte_stream.dart';
import '../network/progress_callback_throttler.dart';

class ClientTransferTuning {
  ClientTransferTuning._();

  static const int uploadStreamBufferSize = 4 * 1024 * 1024;
  static const int uploadProgressMinStepBytes = 8 * 1024 * 1024;
  static const Duration uploadProgressMinInterval = Duration(milliseconds: 500);

  static Stream<List<int>> bufferUploadStream(Stream<List<int>> source) {
    return bufferByteStream(source, uploadStreamBufferSize);
  }

  static ProgressCallbackThrottler uploadProgressThrottler() {
    return ProgressCallbackThrottler(
      minStepBytes: uploadProgressMinStepBytes,
      minInterval: uploadProgressMinInterval,
    );
  }
}
