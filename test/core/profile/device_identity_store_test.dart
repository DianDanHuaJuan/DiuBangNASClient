import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/profile/device_identity_store.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DeviceIdentityStore', () {
    late KeyValueStore keyValueStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      keyValueStore = KeyValueStore(
        prefs: await SharedPreferences.getInstance(),
      );
    });

    test('persists display alias', () async {
      final store = DeviceIdentityStore(keyValueStore: keyValueStore);

      await store.saveDisplayAlias('客厅平板');
      expect(store.displayAlias, '客厅平板');

      await store.clearDisplayAlias();
      expect(store.displayAlias, isNull);
    });

    test('marks avatar revision timestamps', () async {
      final store = DeviceIdentityStore(keyValueStore: keyValueStore);
      final updatedAt = DateTime.utc(2026, 6, 6, 12);

      await store.markAvatarSynced(updatedAt);
      expect(store.avatarUpdatedAt, updatedAt.toLocal());

      await store.clearAvatar();
      expect(store.avatarUpdatedAt, isNull);
    });
  });
}
