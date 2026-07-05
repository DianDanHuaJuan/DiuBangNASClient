/// 文件输入：各模块 Repository、UseCase、Cubit、核心服务实现
/// 文件职责：集中管理应用级依赖注册与按需创建
/// 文件对外接口：configureDependencies、ServiceLocator、serviceLocator
/// 文件包含：configureDependencies、ServiceLocator、serviceLocator
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/key_value_store.dart';
import '../../core/storage/device_token_store.dart';
import '../../core/storage/secure_store.dart';
import '../../core/storage/app_database.dart';
import '../../core/session/current_session.dart';
import '../../core/session/runtime_session_recovery_service.dart';
import '../../core/session/server_availability_controller.dart';
import '../../core/device/client_identity_service.dart';
import '../../core/device/media_storage_service.dart';
import '../../core/device/permission_service.dart';
import '../../core/device/device_file_service.dart';
import '../../core/profile/device_identity_store.dart';
import '../../core/profile/user_profile_store.dart';
import '../../core/network/nas_network_access_policy.dart';
import '../../core/network/client_route_ip_service.dart';
import '../../core/node/unified_node_store.dart';
import '../../core/network/trusted_media_cache_service.dart';
import '../../core/network/trusted_server_http_client_factory.dart';
import '../../core/network/trusted_server_store.dart';
import '../../core/task/task_queue.dart';
import '../../core/task/task_scheduler.dart';
import '../../core/network/nas_api_client.dart';
import '../../core/image/extended_image_cache_coordinator.dart';
import '../../core/protocol/file_protocol_client.dart';
import '../../core/protocol/webdav_file_protocol_client.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/mdns_discovery_data_source.dart';
import '../../features/auth/data/pairing_client.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/repositories/server_discovery_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/repositories/server_discovery_repository.dart';
import '../../features/auth/application/use_cases/bootstrap_device_session_use_case.dart';
import '../../features/auth/application/use_cases/bootstrap_session_use_case.dart';
import '../../features/auth/application/use_cases/restore_session_use_case.dart';
import '../../features/auth/application/use_cases/logout_use_case.dart';
import '../../features/auth/application/use_cases/start_discovery_use_case.dart';
import '../../features/auth/application/use_cases/stop_discovery_use_case.dart';
import '../../features/auth/application/params/connect_server_params.dart';
import '../../features/device_identity/data/device_profile_remote_data_source.dart';
import '../../features/device_identity/data/peer_avatar_cache.dart';
import '../../features/device_identity/domain/device_identity_service.dart';
import '../../features/device_identity/domain/device_profile_sync_service.dart';
import '../../features/benchmark/application/direct_benchmark_runner.dart';
import '../../features/benchmark/application/relay_benchmark_runner.dart';
import '../../features/benchmark/data/benchmark_file_generator.dart';
import '../../features/benchmark/data/benchmark_remote_data_source.dart';
import '../../features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import '../../features/dashboard/data/repositories/dashboard_repository_impl.dart';
import '../../features/dashboard/domain/repositories/dashboard_repository.dart';
import '../../features/dashboard/application/use_cases/load_dashboard_use_case.dart';
import '../../features/files/data/repositories/file_repository_impl.dart';
import '../../features/files/domain/repositories/file_repository.dart';
import '../../features/files/application/use_cases/list_directory_use_case.dart';
import '../../features/files/application/use_cases/create_folder_use_case.dart';
import '../../features/files/application/use_cases/delete_file_use_case.dart';
import '../../features/files/application/use_cases/batch_delete_use_case.dart';
import '../../features/files/application/use_cases/is_root_writable_use_case.dart';
import '../../features/transfer/data/datasources/transfer_local_data_source.dart';
import '../../features/transfer/data/datasources/transfer_executor_data_source.dart';
import '../../features/transfer/data/repositories/transfer_repository_impl.dart';
import '../../features/transfer/domain/repositories/transfer_repository.dart';
import '../../features/transfer/application/use_cases/load_transfer_tasks_use_case.dart';
import '../../features/transfer/application/use_cases/enqueue_download_use_case.dart';
import '../../features/transfer/application/use_cases/enqueue_upload_use_case.dart';
import '../../features/transfer/application/use_cases/observe_transfer_tasks_use_case.dart';
import '../../features/transfer/application/use_cases/pause_transfer_use_case.dart';
import '../../features/transfer/application/use_cases/resume_transfer_use_case.dart';
import '../../features/transfer/application/use_cases/cancel_transfer_use_case.dart';
import '../../features/transfer/application/use_cases/clear_completed_transfer_tasks_use_case.dart';
import '../../features/transfer/application/use_cases/resolve_upload_conflict_use_case.dart';
import '../../features/preview/data/datasources/preview_remote_data_source.dart';
import '../../features/preview/data/repositories/preview_repository_impl.dart';
import '../../features/preview/domain/repositories/preview_repository.dart';
import '../../features/preview/application/use_cases/load_preview_use_case.dart';
import '../../features/preview/application/use_cases/build_original_preview_download_path_use_case.dart';
import '../../features/preview/application/use_cases/resolve_preview_image_source_use_case.dart';
import '../../features/preview/application/use_cases/resolve_preview_video_source_use_case.dart';
import '../../features/preview/application/use_cases/save_original_to_public_storage_use_case.dart';
import '../../features/backup/data/repositories/backup_repository_impl.dart';
import '../../features/backup/data/datasources/backup_local_data_source.dart';
import '../../features/backup/data/datasources/backup_remote_data_source.dart';
import '../../features/backup/application/services/backup_plan_scheduler_service.dart';
import '../../features/backup/application/use_cases/complete_backup_run_use_case.dart';
import '../../features/backup/application/use_cases/create_backup_plan_use_case.dart';
import '../../features/backup/application/use_cases/load_backup_plans_use_case.dart';
import '../../features/backup/application/use_cases/load_recent_backup_runs_use_case.dart';
import '../../features/backup/domain/repositories/backup_repository.dart';
import '../../features/backup/application/use_cases/run_backup_now_use_case.dart';
import '../../features/backup/application/use_cases/toggle_backup_plan_use_case.dart';
import '../../features/relay/data/datasources/relay_remote_data_source.dart';
import '../../features/relay/data/datasources/relay_unread_store.dart';
import '../../features/relay/data/datasources/relay_webdav_transport_client.dart';
import '../../features/relay/data/local/relay_preview_cache.dart';
import '../../features/relay/data/repositories/relay_repository_impl.dart';
import '../../features/relay/domain/repositories/relay_repository.dart';
import '../../features/files/data/datasources/thumbnail_remote_data_source.dart';
import '../../features/files/data/repositories/thumbnail_repository_impl.dart';
import '../../features/files/domain/repositories/thumbnail_repository.dart';
import '../../features/files/application/use_cases/load_batch_thumbnails_use_case.dart';
import '../../features/files/application/use_cases/load_visible_thumbnails_use_case.dart';
import '../../features/files/application/use_cases/get_cached_thumbnail_use_case.dart';
import '../../features/files/application/use_cases/switch_file_root_use_case.dart';
import '../../features/files/application/use_cases/build_file_browser_download_path_use_case.dart';
import '../../features/startup/application/use_cases/resolve_start_route_use_case.dart';
import '../../features/backup/presentation/cubit/backup_cubit.dart';
import '../../features/transfer/presentation/cubit/transfer_cubit.dart';

Future<void> configureDependencies({
  required KeyValueStore keyValueStore,
  required SharedPreferences sharedPreferences,
}) async {
  final secureStore = SecureStore();
  final appDatabase = AppDatabase();
  final currentSession = CurrentSession();
  final permissionService = PermissionService();
  final deviceFileService = DeviceFileService();
  final taskQueue = TaskQueue();
  final taskScheduler = TaskScheduler();

  await ServiceLocator().init(
    keyValueStore: keyValueStore,
    sharedPreferences: sharedPreferences,
    secureStore: secureStore,
    appDatabase: appDatabase,
    currentSession: currentSession,
    permissionService: permissionService,
    deviceFileService: deviceFileService,
    taskQueue: taskQueue,
    taskScheduler: taskScheduler,
  );
}

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  KeyValueStore? _keyValueStore;
  SecureStore? _secureStore;
  AppDatabase? _appDatabase;
  CurrentSession? _currentSession;
  RuntimeSessionRecoveryService? _runtimeSessionRecoveryService;
  ServerAvailabilityController? _serverAvailabilityController;
  UnifiedNodeStore? _unifiedNodeStore;
  ClientIdentityService? _clientIdentityService;
  ClientRouteIpService? _clientRouteIpService;
  PermissionService? _permissionService;
  DeviceFileService? _deviceFileService;
  TaskQueue? _taskQueue;
  TaskScheduler? _taskScheduler;
  TrustedServerStore? _trustedServerStore;
  TrustedServerHttpClientFactory? _trustedServerHttpClientFactory;
  TrustedMediaCacheService? _trustedMediaCacheService;
  PairingClient? _pairingClient;
  BenchmarkRemoteDataSource? _benchmarkRemoteDataSource;
  BenchmarkFileGenerator? _benchmarkFileGenerator;
  DirectBenchmarkRunner? _directBenchmarkRunner;
  RelayRemoteDataSource? _relayRemoteDataSource;
  RelayWebdavTransportClient? _relayTransportClient;
  RelayBenchmarkRunner? _relayBenchmarkRunner;

  String? _lastServerUrl;
  NasApiClient? _apiClient;
  FileProtocolClient? _fileProtocolClient;
  AuthLocalDataSource? _authLocalDataSource;
  DeviceTokenStore? _deviceTokenStore;
  AuthRepository? _authRepository;
  DashboardRepository? _dashboardRepository;
  FileRepository? _fileRepository;
  TransferRepository? _transferRepository;
  PreviewRepository? _previewRepository;
  BackupRepository? _backupRepository;
  BackupPlanSchedulerService? _backupPlanScheduler;
  RelayRepository? _relayRepository;
  RelayUnreadStore? _relayUnreadStore;
  RelayPreviewCache? _relayPreviewCache;
  UserProfileStore? _userProfileStore;
  DeviceProfileRemoteDataSource? _deviceProfileRemoteDataSource;
  DeviceIdentityService? _deviceIdentityService;
  DeviceProfileSyncService? _deviceProfileSyncService;
  PeerAvatarCache? _peerAvatarCache;
  ThumbnailRepository? _thumbnailRepository;
  ResolvePreviewImageSourceUseCase? _resolvePreviewImageSourceUseCase;
  ResolvePreviewVideoSourceUseCase? _resolvePreviewVideoSourceUseCase;
  ExtendedImageCacheCoordinator? _extendedImageCacheCoordinator;

  TransferCubit? _transferCubit;

  Future<void> init({
    required KeyValueStore keyValueStore,
    required SharedPreferences sharedPreferences,
    required SecureStore secureStore,
    required AppDatabase appDatabase,
    required CurrentSession currentSession,
    required PermissionService permissionService,
    required DeviceFileService deviceFileService,
    required TaskQueue taskQueue,
    required TaskScheduler taskScheduler,
  }) async {
    _keyValueStore = keyValueStore;
    _secureStore = secureStore;
    _appDatabase = appDatabase;
    _currentSession = currentSession;
    _runtimeSessionRecoveryService = null;
    _serverAvailabilityController = ServerAvailabilityController();
    _unifiedNodeStore = UnifiedNodeStore();
    _currentSession!.bindState(_unifiedNodeStore!);
    _unifiedNodeStore!.applyCachedPeerClients(_keyValueStore!.getPeerNodes());
    _clientIdentityService = ClientIdentityService(prefs: sharedPreferences);
    _clientRouteIpService = ClientRouteIpService();
    _permissionService = permissionService;
    _deviceFileService = deviceFileService;
    _taskQueue = taskQueue;
    _taskScheduler = taskScheduler;
    _trustedServerStore = TrustedServerStore(secureStore: secureStore);
    await _trustedServerStore!.initialize();
    _trustedServerHttpClientFactory = TrustedServerHttpClientFactory(
      trustedServerStore: _trustedServerStore!,
    );
    _trustedMediaCacheService = TrustedMediaCacheService(
      trustedHttpClientFactory: _trustedServerHttpClientFactory!,
    );
    _pairingClient = PairingClient(
      trustedServerStore: _trustedServerStore!,
      deviceIdProvider: _clientIdentityService!.getDeviceId,
      deviceNameProvider: _clientIdentityService!.getDeviceName,
      devicePlatformProvider: _clientIdentityService!.getDeviceType,
      deviceBrandProvider: _clientIdentityService!.getDeviceBrand,
      deviceModelProvider: _clientIdentityService!.getDeviceModel,
    );

    _lastServerUrl = _keyValueStore?.getLastServerUrl();
  }

  KeyValueStore get keyValueStore => _keyValueStore!;
  SecureStore get secureStore => _secureStore!;
  DeviceTokenStore get deviceTokenStore =>
      _deviceTokenStore ??= DeviceTokenStore(secureStore: _secureStore!);
  AppDatabase get appDatabase => _appDatabase!;
  CurrentSession get currentSession => _currentSession!;
  RuntimeSessionRecoveryService get runtimeSessionRecoveryService =>
      _runtimeSessionRecoveryService ??= RuntimeSessionRecoveryService(
        restoreSessionUseCase: restoreSessionUseCase,
        currentSession: currentSession,
        applyBaseUrl: setBaseUrl,
      );
  ServerAvailabilityController get serverAvailabilityController =>
      _serverAvailabilityController ??= ServerAvailabilityController();
  UnifiedNodeStore get unifiedNodeStore =>
      _unifiedNodeStore ??= UnifiedNodeStore();
  ClientIdentityService get clientIdentityService => _clientIdentityService!;
  ClientRouteIpService get clientRouteIpService => _clientRouteIpService!;
  AuthLocalDataSource get authLocalDataSource =>
      _authLocalDataSource ??= AuthLocalDataSource(
        secureStore: _secureStore!,
        keyValueStore: _keyValueStore!,
        deviceTokenStore: deviceTokenStore,
      );
  PermissionService get permissionService => _permissionService!;
  DeviceFileService get deviceFileService => _deviceFileService!;
  TaskQueue get taskQueue => _taskQueue!;
  TaskScheduler get taskScheduler => _taskScheduler!;
  TrustedServerStore get trustedServerStore => _trustedServerStore!;
  TrustedServerHttpClientFactory get trustedServerHttpClientFactory =>
      _trustedServerHttpClientFactory!;
  TrustedMediaCacheService get trustedMediaCacheService =>
      _trustedMediaCacheService!;
  PairingClient get pairingClient => _pairingClient!;
  BenchmarkRemoteDataSource get benchmarkRemoteDataSource {
    _benchmarkRemoteDataSource ??= BenchmarkRemoteDataSource(
      apiClient: apiClient,
    );
    return _benchmarkRemoteDataSource!;
  }

  BenchmarkFileGenerator get benchmarkFileGenerator {
    _benchmarkFileGenerator ??= BenchmarkFileGenerator(
      deviceFileService: deviceFileService,
    );
    return _benchmarkFileGenerator!;
  }

  DirectBenchmarkRunner get directBenchmarkRunner {
    _directBenchmarkRunner ??= DirectBenchmarkRunner(
      remoteDataSource: benchmarkRemoteDataSource,
      fileGenerator: benchmarkFileGenerator,
      deviceFileService: deviceFileService,
      mediaStorageService: MediaStorageService(),
      currentSession: currentSession,
    );
    return _directBenchmarkRunner!;
  }

  RelayRemoteDataSource get relayRemoteDataSource {
    _relayRemoteDataSource ??= RelayRemoteDataSource(apiClient: apiClient);
    return _relayRemoteDataSource!;
  }

  RelayWebdavTransportClient get relayTransportClient {
    _relayTransportClient ??= RelayWebdavTransportClient(apiClient: apiClient);
    return _relayTransportClient!;
  }

  RelayBenchmarkRunner get relayBenchmarkRunner {
    _relayBenchmarkRunner ??= RelayBenchmarkRunner(
      relayRemoteDataSource: relayRemoteDataSource,
      transportClient: relayTransportClient,
      fileGenerator: benchmarkFileGenerator,
      deviceFileService: deviceFileService,
      mediaStorageService: MediaStorageService(),
      currentSession: currentSession,
    );
    return _relayBenchmarkRunner!;
  }

  String? get lastServerUrl => _lastServerUrl;

  Future<void> setBaseUrl(String baseUrl) async {
    final normalizedBaseUrl = NasNetworkAccessPolicy.normalizeServerUrl(
      baseUrl,
    );
    _lastServerUrl = normalizedBaseUrl;
    _apiClient = NasApiClient(
      baseUrl: normalizedBaseUrl,
      session: _currentSession!,
      deviceIdProvider: _clientIdentityService?.getDeviceId,
      deviceNameProvider: _clientIdentityService!.getDeviceName,
      sessionRecoveryHandler: runtimeSessionRecoveryService.recoverSession,
      trustedHttpClientFactory: trustedServerHttpClientFactory,
    );
    await _apiClient!.warmupConnection();

    _fileProtocolClient = WebdavFileProtocolClient(
      baseUrl: _currentSession?.webdavBaseUrl ?? normalizedBaseUrl,
      authHeaderProvider: () => _currentSession?.authHeader,
      clientIdProvider: _clientIdentityService?.getDeviceId,
      clientNameProvider: _clientIdentityService?.getDeviceName,
      trustedHttpClientFactory: trustedServerHttpClientFactory,
    );

    _authRepository = null;
    _dashboardRepository = null;
    _fileRepository = null;
    _transferRepository = null;
    _previewRepository = null;
    _backupRepository = null;
    _relayRepository = null;
    _backupPlanScheduler = null;
    _thumbnailRepository = null;
    _resolvePreviewImageSourceUseCase = null;
    _resolvePreviewVideoSourceUseCase = null;
    _transferCubit = null;
    _benchmarkRemoteDataSource = null;
    _benchmarkFileGenerator = null;
    _directBenchmarkRunner = null;
    _relayRemoteDataSource = null;
    _relayTransportClient = null;
    _relayBenchmarkRunner = null;
    _deviceProfileRemoteDataSource = null;
  }

  NasApiClient get apiClient {
    if (_apiClient == null) {
      String? url = _lastServerUrl;
      if (url == null && _keyValueStore != null) {
        url = _keyValueStore!.getLastServerUrl();
        if (url != null) {
          try {
            _lastServerUrl = NasNetworkAccessPolicy.normalizeServerUrl(url);
          } catch (_) {
            _lastServerUrl = null;
          }
        }
        url = _lastServerUrl;
      }
      if (url != null) {
        _currentSession ??= CurrentSession();
        _apiClient = NasApiClient(
          baseUrl: url,
          session: _currentSession!,
          deviceIdProvider: _clientIdentityService?.getDeviceId,
          deviceNameProvider: _clientIdentityService!.getDeviceName,
          sessionRecoveryHandler: runtimeSessionRecoveryService.recoverSession,
          trustedHttpClientFactory: trustedServerHttpClientFactory,
        );
        return _apiClient!;
      }
      _currentSession ??= CurrentSession();
      _apiClient = NasApiClient(
        baseUrl: 'https://localhost:8080',
        session: _currentSession!,
        deviceIdProvider: _clientIdentityService?.getDeviceId,
        deviceNameProvider: _clientIdentityService!.getDeviceName,
        sessionRecoveryHandler: runtimeSessionRecoveryService.recoverSession,
        trustedHttpClientFactory: trustedServerHttpClientFactory,
      );
      return _apiClient!;
    }
    return _apiClient!;
  }

  FileProtocolClient get fileProtocolClient {
    if (_fileProtocolClient == null) {
      final baseUrl = _currentSession?.webdavBaseUrl ??
          _lastServerUrl ??
          'https://localhost:8080';
      _fileProtocolClient = WebdavFileProtocolClient(
        baseUrl: baseUrl,
        authHeaderProvider: () => _currentSession?.authHeader,
        clientIdProvider: _clientIdentityService?.getDeviceId,
        clientNameProvider: _clientIdentityService?.getDeviceName,
        trustedHttpClientFactory: trustedServerHttpClientFactory,
      );
    }
    return _fileProtocolClient!;
  }

  AuthRepository get authRepository {
    _authRepository ??= AuthRepositoryImpl(
      remoteDataSource: AuthRemoteDataSource(
        deviceIdProvider: _clientIdentityService?.getDeviceId,
        deviceNameProvider: _clientIdentityService!.getDeviceName,
        trustedHttpClientFactory: trustedServerHttpClientFactory,
      ),
      localDataSource: authLocalDataSource,
      currentSession: _currentSession!,
      unifiedNodeStore: unifiedNodeStore,
      clientIdentityService: _clientIdentityService!,
    );
    return _authRepository!;
  }

  DashboardRepository get dashboardRepository {
    _dashboardRepository ??= DashboardRepositoryImpl(
      remoteDataSource: DashboardRemoteDataSource(apiClient: apiClient),
    );
    return _dashboardRepository!;
  }

  FileRepository get fileRepository {
    _fileRepository ??= FileRepositoryImpl(
      protocolClient: fileProtocolClient,
      apiClient: apiClient,
    );
    return _fileRepository!;
  }

  BootstrapDeviceSessionUseCase get bootstrapDeviceSessionUseCase {
    return BootstrapDeviceSessionUseCase(repository: authRepository);
  }

  BootstrapSessionUseCase get bootstrapSessionUseCase {
    return BootstrapSessionUseCase(repository: authRepository);
  }

  ConnectServerParams connectServerParams({
    required String serverUrl,
    required String username,
    required String password,
    bool rememberCredentials = true,
  }) {
    return ConnectServerParams(
      serverUrl: serverUrl,
      username: username,
      password: password,
      rememberCredentials: rememberCredentials,
    );
  }

  RestoreSessionUseCase get restoreSessionUseCase {
    return RestoreSessionUseCase(repository: authRepository);
  }

  LogoutUseCase get logoutUseCase {
    return LogoutUseCase(repository: authRepository);
  }

  MdnsDiscoveryDataSource get mdnsDiscoveryDataSource {
    return MdnsDiscoveryDataSource();
  }

  ServerDiscoveryRepository get serverDiscoveryRepository {
    return ServerDiscoveryRepositoryImpl(dataSource: mdnsDiscoveryDataSource);
  }

  StartDiscoveryUseCase get startDiscoveryUseCase {
    return StartDiscoveryUseCase(repository: serverDiscoveryRepository);
  }

  StopDiscoveryUseCase get stopDiscoveryUseCase {
    return StopDiscoveryUseCase(repository: serverDiscoveryRepository);
  }

  LoadDashboardUseCase get loadDashboardUseCase {
    return LoadDashboardUseCase(repository: dashboardRepository);
  }

  ListDirectoryUseCase get listDirectoryUseCase {
    return ListDirectoryUseCase(repository: fileRepository);
  }

  CreateFolderUseCase get createFolderUseCase {
    return CreateFolderUseCase(repository: fileRepository);
  }

  DeleteFileUseCase get deleteFileUseCase {
    return DeleteFileUseCase(repository: fileRepository);
  }

  BatchDeleteUseCase get batchDeleteUseCase {
    return BatchDeleteUseCase(repository: fileRepository);
  }

  TransferRepository get transferRepository {
    _transferRepository ??= TransferRepositoryImpl(
      localDataSource: TransferLocalDataSource(keyValueStore: _keyValueStore!),
      executorDataSource: TransferExecutorDataSource(
        protocolClient: fileProtocolClient,
      ),
    );
    return _transferRepository!;
  }

  PreviewRepository get previewRepository {
    _previewRepository ??= PreviewRepositoryImpl(
      remoteDataSource: PreviewRemoteDataSource(apiClient: apiClient),
    );
    return _previewRepository!;
  }

  BackupRepository get backupRepository {
    _backupRepository ??= BackupRepositoryImpl(
      transferRepository: transferRepository,
      currentSession: currentSession,
      deviceIdProvider: clientIdentityService.getDeviceId,
      localDataSource: BackupLocalDataSource(appDatabase: appDatabase),
      remoteDataSource: BackupRemoteDataSource(apiClient: apiClient),
    );
    return _backupRepository!;
  }

  BackupPlanSchedulerService get backupPlanScheduler {
    _backupPlanScheduler ??= BackupPlanSchedulerService(
      localDataSource: BackupLocalDataSource(appDatabase: appDatabase),
      profileResolver: BackupPlanExecutionProfileResolver(
        authLocalDataSource: authLocalDataSource,
        clientIdentityService: clientIdentityService,
        trustedServerStore: trustedServerStore,
      ),
    );
    return _backupPlanScheduler!;
  }

  RelayRepository get relayRepository {
    _relayRepository ??= RelayRepositoryImpl(
      remoteDataSource: relayRemoteDataSource,
      transportClient: relayTransportClient,
      deviceFileService: deviceFileService,
      mediaStorageService: MediaStorageService(),
    );
    return _relayRepository!;
  }

  RelayUnreadStore get relayUnreadStore {
    _relayUnreadStore ??= RelayUnreadStore(keyValueStore: keyValueStore);
    return _relayUnreadStore!;
  }

  RelayPreviewCache get relayPreviewCache {
    _relayPreviewCache ??= RelayPreviewCache(keyValueStore: keyValueStore);
    return _relayPreviewCache!;
  }

  UserProfileStore get userProfileStore {
    _userProfileStore ??= DeviceIdentityStore(keyValueStore: keyValueStore);
    return _userProfileStore!;
  }

  DeviceProfileRemoteDataSource get deviceProfileRemoteDataSource {
    _deviceProfileRemoteDataSource ??= DeviceProfileRemoteDataSource(
      apiClient: apiClient,
    );
    return _deviceProfileRemoteDataSource!;
  }

  DeviceIdentityService get deviceIdentityService {
    _deviceIdentityService ??= DeviceIdentityService(
      identityStore: userProfileStore,
      remoteDataSource: deviceProfileRemoteDataSource,
      clientIdentityService: clientIdentityService,
      unifiedNodeStore: unifiedNodeStore,
    );
    return _deviceIdentityService!;
  }

  DeviceProfileSyncService get deviceProfileSyncService {
    _deviceProfileSyncService ??= DeviceProfileSyncService(
      remoteDataSource: deviceProfileRemoteDataSource,
      unifiedNodeStore: unifiedNodeStore,
    );
    return _deviceProfileSyncService!;
  }

  PeerAvatarCache get peerAvatarCache {
    _peerAvatarCache ??= PeerAvatarCache(
      remoteDataSource: deviceProfileRemoteDataSource,
    );
    return _peerAvatarCache!;
  }

  LoadTransferTasksUseCase get loadTransferTasksUseCase {
    return LoadTransferTasksUseCase(repository: transferRepository);
  }

  ObserveTransferTasksUseCase get observeTransferTasksUseCase {
    return ObserveTransferTasksUseCase(repository: transferRepository);
  }

  EnqueueDownloadUseCase get enqueueDownloadUseCase {
    return EnqueueDownloadUseCase(repository: transferRepository);
  }

  EnqueueUploadUseCase get enqueueUploadUseCase {
    return EnqueueUploadUseCase(repository: transferRepository);
  }

  PauseTransferUseCase get pauseTransferUseCase {
    return PauseTransferUseCase(repository: transferRepository);
  }

  ResumeTransferUseCase get resumeTransferUseCase {
    return ResumeTransferUseCase(repository: transferRepository);
  }

  CancelTransferUseCase get cancelTransferUseCase {
    return CancelTransferUseCase(repository: transferRepository);
  }

  ClearCompletedTransferTasksUseCase get clearCompletedTransferTasksUseCase {
    return ClearCompletedTransferTasksUseCase(repository: transferRepository);
  }

  ResolveUploadConflictUseCase get resolveUploadConflictUseCase {
    return ResolveUploadConflictUseCase(repository: transferRepository);
  }

  LoadPreviewUseCase get loadPreviewUseCase {
    return LoadPreviewUseCase(repository: previewRepository);
  }

  BuildOriginalPreviewDownloadPathUseCase
  get buildOriginalPreviewDownloadPathUseCase {
    return BuildOriginalPreviewDownloadPathUseCase(
      deviceFileService: deviceFileService,
    );
  }

  SaveOriginalToPublicStorageUseCase get saveOriginalToPublicStorageUseCase {
    return SaveOriginalToPublicStorageUseCase(
      deviceFileService: deviceFileService,
      mediaStorageService: MediaStorageService(),
    );
  }

  ResolvePreviewImageSourceUseCase get resolvePreviewImageSourceUseCase {
    _resolvePreviewImageSourceUseCase ??= ResolvePreviewImageSourceUseCase(
      baseUrl: apiClient.baseUrl,
    );
    return _resolvePreviewImageSourceUseCase!;
  }

  ResolvePreviewVideoSourceUseCase get resolvePreviewVideoSourceUseCase {
    _resolvePreviewVideoSourceUseCase ??= ResolvePreviewVideoSourceUseCase(
      baseUrl: apiClient.baseUrl,
    );
    return _resolvePreviewVideoSourceUseCase!;
  }

  ThumbnailRepository get thumbnailRepository {
    _thumbnailRepository ??= ThumbnailRepositoryImpl(
      remoteDataSource: ThumbnailRemoteDataSource(apiClient: apiClient),
    );
    return _thumbnailRepository!;
  }

  LoadBatchThumbnailsUseCase get loadBatchThumbnailsUseCase {
    return LoadBatchThumbnailsUseCase(repository: thumbnailRepository);
  }

  LoadVisibleThumbnailsUseCase get loadVisibleThumbnailsUseCase {
    return LoadVisibleThumbnailsUseCase(repository: thumbnailRepository);
  }

  GetCachedThumbnailUseCase get getCachedThumbnailUseCase {
    return GetCachedThumbnailUseCase(repository: thumbnailRepository);
  }

  SwitchFileRootUseCase get switchFileRootUseCase {
    return SwitchFileRootUseCase(currentSession: currentSession);
  }

  BuildFileBrowserDownloadPathUseCase get buildFileBrowserDownloadPathUseCase {
    return BuildFileBrowserDownloadPathUseCase(
      deviceFileService: deviceFileService,
    );
  }

  IsRootWritableUseCase get isRootWritableUseCase {
    return IsRootWritableUseCase(currentSession: currentSession);
  }

  ExtendedImageCacheCoordinator get extendedImageCacheCoordinator {
    _extendedImageCacheCoordinator ??= ExtendedImageCacheCoordinator(
      mediaCacheService: trustedMediaCacheService,
    );
    return _extendedImageCacheCoordinator!;
  }

  ResolveStartRouteUseCase get resolveStartRouteUseCase {
    return ResolveStartRouteUseCase(
      keyValueStore: keyValueStore,
      authLocalDataSource: authLocalDataSource,
    );
  }

  RunBackupNowUseCase get runBackupNowUseCase {
    return RunBackupNowUseCase(repository: backupRepository);
  }

  CreateBackupPlanUseCase get createBackupPlanUseCase {
    return CreateBackupPlanUseCase(repository: backupRepository);
  }

  LoadBackupPlansUseCase get loadBackupPlansUseCase {
    return LoadBackupPlansUseCase(repository: backupRepository);
  }

  LoadRecentBackupRunsUseCase get loadRecentBackupRunsUseCase {
    return LoadRecentBackupRunsUseCase(repository: backupRepository);
  }

  CompleteBackupRunUseCase get completeBackupRunUseCase {
    return CompleteBackupRunUseCase(repository: backupRepository);
  }

  ToggleBackupPlanUseCase get toggleBackupPlanUseCase {
    return ToggleBackupPlanUseCase(repository: backupRepository);
  }

  BackupCubit get backupCubit {
    return BackupCubit(
      runBackupNowUseCase: runBackupNowUseCase,
      completeBackupRunUseCase: completeBackupRunUseCase,
      cancelTransferUseCase: cancelTransferUseCase,
    );
  }

  TransferCubit get transferCubit {
    _transferCubit ??= TransferCubit(
      loadTasksUseCase: loadTransferTasksUseCase,
      enqueueDownloadUseCase: enqueueDownloadUseCase,
      enqueueUploadUseCase: enqueueUploadUseCase,
      observeTransferTasksUseCase: observeTransferTasksUseCase,
      pauseTransferUseCase: pauseTransferUseCase,
      resumeTransferUseCase: resumeTransferUseCase,
      cancelTransferUseCase: cancelTransferUseCase,
      clearCompletedTransferTasksUseCase: clearCompletedTransferTasksUseCase,
      resolveUploadConflictUseCase: resolveUploadConflictUseCase,
    );
    return _transferCubit!;
  }
}

final serviceLocator = ServiceLocator();
