import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/device_display_resolver.dart';

void main() {
  group('DeviceDisplayResolver', () {
    test('prefers alias over hardware and platform', () {
      expect(
        DeviceDisplayResolver.publicDisplayName(
          alias: '客厅平板',
          hardwareName: 'Xiaomi Pad',
          platform: 'android',
          fallback: 'phone-01',
        ),
        '客厅平板',
      );
    });

    test('drops technical scan aliases', () {
      expect(
        DeviceDisplayResolver.publicDisplayName(
          alias: '扫码接入1234',
          platform: 'ios',
          fallback: 'phone-01',
        ),
        'iOS设备',
      );
    });

    test('localPublicDisplayName falls back to hardware name', () async {
      expect(
        DeviceDisplayResolver.localPublicDisplayName(
          alias: null,
          hardwareName: 'DESKTOP-ABC',
        ),
        'DESKTOP-ABC',
      );
    });
  });
}
