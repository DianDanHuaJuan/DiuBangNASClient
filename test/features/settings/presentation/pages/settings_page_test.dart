/// 文件输入：SettingsPage
/// 文件职责：验证设置页会展示备份任务入口并响应点击
/// 文件对外接口：main
/// 文件包含：main
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/client_identity_service.dart';
import 'package:nasclient/core/node/unified_node_store.dart';
import 'package:nasclient/core/profile/user_profile_store.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/features/device_identity/data/device_profile_remote_data_source.dart';
import 'package:nasclient/features/device_identity/domain/device_identity_service.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 输入：Flutter test runtime。
/// 职责：覆盖设置页中的备份任务入口展示和点击行为。
/// 对外接口：main。
void main() {
  group('SettingsPage', () {
    testWidgets('shows backup task entry and triggers callback', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final keyValueStore = KeyValueStore(prefs: prefs);
      var tapped = false;

      final profileStore = UserProfileStore(keyValueStore: keyValueStore);
      final identityService = ClientIdentityService(prefs: prefs);
      final deviceIdentityService = DeviceIdentityService(
        identityStore: profileStore,
        remoteDataSource: DeviceProfileRemoteDataSource(
          apiClient: NasApiClient(
            baseUrl: 'http://localhost',
            session: CurrentSession(),
          ),
        ),
        clientIdentityService: identityService,
        unifiedNodeStore: UnifiedNodeStore(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            onBackupTap: () {
              tapped = true;
            },
            userProfileStore: profileStore,
            clientIdentityService: identityService,
            deviceIdentityService: deviceIdentityService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('文件备份'), findsOneWidget);
      expect(find.text('设备身份'), findsOneWidget);
      expect(find.text('个人资料'), findsNothing);
      expect(find.text('备份任务'), findsNothing);

      await tester.tap(find.text('文件备份'));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });
}
