import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/device_id_normalizer.dart';

void main() {
  group('DeviceIdNormalizer', () {
    test('trims and replaces whitespace with dashes', () {
      expect(
        DeviceIdNormalizer.normalize(' windows pc 123 '),
        'windows-pc-123',
      );
    });

    test('returns null for empty values', () {
      expect(DeviceIdNormalizer.normalize('   '), isNull);
      expect(DeviceIdNormalizer.normalize(null), isNull);
    });
  });
}
