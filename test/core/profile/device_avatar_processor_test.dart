import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nasclient/core/profile/device_avatar_processor.dart';

void main() {
  group('DeviceAvatarProcessor', () {
    test('compresses large square image below 30KB', () {
      final source = img.Image(width: 2000, height: 2000);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, x % 255, y % 255, (x + y) % 255);
        }
      }

      final bytes = DeviceAvatarProcessor.encodeAvatarJpeg(source);

      expect(bytes.length, lessThanOrEqualTo(DeviceAvatarProcessor.targetMaxBytes));
      expect(bytes.length, greaterThan(1024));
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
    });
  });
}
