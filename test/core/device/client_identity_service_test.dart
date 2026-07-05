import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/client_identity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClientIdentityService', () {
    test('prefers Android ID and overwrites legacy cached ids', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'client_device_id': 'android_legacy_generated_id',
      });
      final prefs = await SharedPreferences.getInstance();
      var resolverCallCount = 0;
      final service = ClientIdentityService(
        prefs: prefs,
        isAndroidPlatform: () => true,
        androidIdResolver: () async {
          resolverCallCount += 1;
          return 'A1B2C3D4E5F6';
        },
      );

      final first = await service.getDeviceId();
      final second = await service.getDeviceId();

      expect(first, 'a1b2c3d4e5f6');
      expect(second, 'a1b2c3d4e5f6');
      expect(prefs.getString('client_device_id'), 'a1b2c3d4e5f6');
      expect(resolverCallCount, 1);
    });

    test('falls back to stored id when Android ID is unavailable', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'client_device_id': 'legacy_device_id',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = ClientIdentityService(
        prefs: prefs,
        isAndroidPlatform: () => true,
        androidIdResolver: () async => null,
      );

      final deviceId = await service.getDeviceId();

      expect(deviceId, 'legacy_device_id');
      expect(prefs.getString('client_device_id'), 'legacy_device_id');
    });
  });
}
