import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/error/app_failure.dart';
import 'package:nasclient/core/node/unified_node_store.dart';
import 'package:nasclient/core/realtime/realtime_connection_state.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/core/use_case/no_params.dart';
import 'package:nasclient/features/dashboard/application/use_cases/load_dashboard_use_case.dart';
import 'package:nasclient/features/dashboard/domain/entities/dashboard_summary_entity.dart';
import 'package:nasclient/features/dashboard/domain/entities/device_info_entity.dart';
import 'package:nasclient/features/dashboard/domain/entities/storage_info_entity.dart';
import 'package:nasclient/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:nasclient/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:nasclient/features/dashboard/presentation/cubit/dashboard_state.dart';

void main() {
  group('DashboardCubit', () {
    test('retries transient failures before showing error', () async {
      var attempts = 0;
      final cubit = DashboardCubit(
        loadDashboardUseCase: LoadDashboardUseCase(
          repository: _FakeDashboardRepository(
            onLoad: () async {
              attempts += 1;
              if (attempts < 2) {
                return Failure(
                  const AppFailure(code: 'TIMEOUT', message: 'Connection timeout'),
                );
              }
              return Success(_sampleSummary());
            },
          ),
        ),
        unifiedNodeStore: UnifiedNodeStore(),
      );

      await cubit.loadDashboard();

      expect(attempts, 2);
      expect(cubit.state, isA<DashboardLoaded>());
      await cubit.close();
    });

    test('defers initial error while realtime is connecting', () async {
      final cubit = DashboardCubit(
        loadDashboardUseCase: LoadDashboardUseCase(
          repository: _FakeDashboardRepository(
            onLoad: () async => Failure(
              const AppFailure(code: 'TIMEOUT', message: 'Connection timeout'),
            ),
          ),
        ),
        unifiedNodeStore: UnifiedNodeStore(),
      );
      cubit.applyRealtimeConnectionStatus(RealtimeConnectionStatus.connecting);

      await cubit.loadDashboard();

      expect(cubit.state, isA<DashboardLoading>());
      await cubit.close();
    });
  });
}

DashboardSummaryEntity _sampleSummary() {
  return DashboardSummaryEntity(
    deviceInfo: DeviceInfoEntity(
      deviceName: 'device-1',
      model: 'model',
      brand: 'brand',
      status: 'online',
      uptime: 1,
      batteryLevel: 1,
      batteryPercent: 100,
      isCharging: false,
    ),
    storageInfo: StorageInfoEntity(
      totalBytes: 100,
      usedBytes: 10,
      availableBytes: 90,
    ),
    localIp: '192.168.1.10',
  );
}

class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository({required this.onLoad});

  final Future<AppResult<DashboardSummaryEntity>> Function() onLoad;

  @override
  Future<AppResult<DashboardSummaryEntity>> getDashboardSummary() => onLoad();

  @override
  Future<AppResult<DeviceInfoEntity>> getDeviceInfo() {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<StorageInfoEntity>> getStorageInfo() {
    throw UnimplementedError();
  }
}
