import 'package:flutter_test/flutter_test.dart';

import 'package:nasclient/app/app.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:nasclient/features/startup/application/use_cases/resolve_start_route_use_case.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final resolver = ResolveStartRouteUseCase(
      keyValueStore: KeyValueStore(prefs: prefs),
      authLocalDataSource: _BootAuthLocalDataSource(),
      onlineProbe: (_) async => false,
    );
    await tester.pumpWidget(App(resolveStartRouteUseCase: resolver));
    expect(find.byType(App), findsOneWidget);
  });
}

class _BootAuthLocalDataSource implements AuthLocalDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> hasRecoverableSession() async => false;
}
