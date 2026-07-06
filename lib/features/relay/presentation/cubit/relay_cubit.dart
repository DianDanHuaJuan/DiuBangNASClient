import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/device/device_file_service.dart';
import '../../../../core/device/local_media_picker.dart';
import '../../../../core/node/unified_node.dart';
import '../../../../core/node/unified_node_store.dart';
import '../../../../core/node/device_display_extensions.dart';
import '../../../../core/node/device_display_resolver.dart';
import '../../../device_identity/domain/device_profile_sync_service.dart';
import '../../../../core/profile/user_profile_store.dart';
import '../../application/services/relay_thumbnail_generator.dart';
import '../../data/datasources/relay_unread_store.dart';
import '../../data/local/relay_preview_cache.dart';
import '../../data/local/relay_thumbnail_cache_manager.dart';
import '../../data/models/relay_transfer_dto.dart';
import '../../debug/relay_diagnostic_log.dart';
import '../../domain/entities/relay_config_entity.dart';
import '../../domain/entities/relay_transfer_entity.dart';
import '../../domain/relay_media_kind.dart';
import '../../domain/relay_thumbnail_paths.dart';
import '../../domain/repositories/relay_repository.dart';
import 'peer_conversation_history.dart';
import 'relay_state.dart';
import 'relay_unread_tracker.dart';

class RelayCubit extends Cubit<RelayState> {
  RelayCubit({
    required RelayRepository relayRepository,
    required DeviceFileService deviceFileService,
    required UnifiedNodeStore unifiedNodeStore,
    RelayPreviewCache? relayPreviewCache,
    UserProfileStore? userProfileStore,
    RelayUnreadStore? relayUnreadStore,
    RelayThumbnailCacheManager? thumbnailCacheManager,
    RelayThumbnailGenerator? thumbnailGenerator,
    DeviceProfileSyncService? deviceProfileSyncService,
  }) : _relayRepository = relayRepository,
       _deviceFileService = deviceFileService,
       _unifiedNodeStore = unifiedNodeStore,
       _previewCache = relayPreviewCache,
       _userProfileStore = userProfileStore,
       _relayUnreadStore = relayUnreadStore,
       _thumbnailCacheManager =
           thumbnailCacheManager ?? RelayThumbnailCacheManager(),
       _thumbnailGenerator = thumbnailGenerator ?? const RelayThumbnailGenerator(),
       _deviceProfileSyncService = deviceProfileSyncService,
       super(const RelayState()) {
    _nodeStoreSubscription = _unifiedNodeStore.stream.listen((_) {
      if (!isClosed) {
        emit(_buildState());
      }
    });
    unawaited(_previewCache?.load());
  }

  final RelayRepository _relayRepository;
  final DeviceFileService _deviceFileService;
  final UnifiedNodeStore _unifiedNodeStore;
  final RelayPreviewCache? _previewCache;
  final UserProfileStore? _userProfileStore;
  final RelayUnreadStore? _relayUnreadStore;
  final RelayThumbnailCacheManager _thumbnailCacheManager;
  final RelayThumbnailGenerator _thumbnailGenerator;
  final DeviceProfileSyncService? _deviceProfileSyncService;
  final RelayUnreadTracker _unreadTracker = RelayUnreadTracker();
  late final StreamSubscription<int> _nodeStoreSubscription;
  Timer? _thumbnailRefreshDebounce;

  RelayPreviewCache? get previewCache => _previewCache;

  String? get localAvatarPath => _userProfileStore?.avatarPath;

  String get localDisplayName {
    return DeviceDisplayResolver.localPublicDisplayName(
      alias: _userProfileStore?.displayAlias,
      hardwareName: _unifiedNodeStore.selfClient?.identity.deviceName,
      fallback: _unifiedNodeStore.selfClient?.publicDisplayName ?? '本机',
    );
  }

  bool get hasUnread => state.hasUnread;

  String? get currentClientId {
    final clientId = _unifiedNodeStore.authState.clientId?.trim();
    if (clientId == null || clientId.isEmpty) {
      return null;
    }
    return clientId;
  }

  Map<String, dynamic>? get _relayCapability {
    final relay =
        _unifiedNodeStore.currentServer?.server?.capabilities?['relay'];
    if (relay is Map<String, dynamic>) {
      return relay;
    }
    if (relay is Map) {
      return relay.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  bool get isRelayEnabled => (_relayCapability?['enabled'] as bool?) ?? false;

  bool get hasRelayConfiguration => _relayCapability != null;

  String get relayRetentionDescription => RelayConfigEntity.retentionDescription;

  List<UnifiedNode> get peers => _buildPeers(state.transfers);

  bool get hasPeers => peers.isNotEmpty;

  UnifiedNode? peerById(String clientId) {
    for (final peer in peers) {
      if (peer.identity.clientId == clientId) {
        return peer;
      }
    }
    return null;
  }

  Future<void> loadHistory({
    bool showLoading = true,
    bool preserveFeedback = false,
  }) async {
    if (showLoading) {
      emit(_buildState(isLoading: true, message: null, errorMessage: null));
    }

    final result = await _relayRepository.loadHistory();
    result.when(
      success: (transfers) {
        final mergedTransfers = _mergeTransfersWithExisting(transfers);
        _ingestTransferPeers(mergedTransfers);
        _recomputeUnreadFromHistory(mergedTransfers);
        emit(
          _buildState(
            isLoading: false,
            transfers: mergedTransfers,
            errorMessage: preserveFeedback ? state.errorMessage : null,
            message: preserveFeedback ? state.message : null,
          ),
        );
        unawaited(
          _previewCache?.pruneStale(
            mergedTransfers.map((t) => t.transferId).toSet(),
          ),
        );
      },
      failure: (failure) {
        relayDiag(
          'loadHistory_fail',
          fields: <String, Object?>{'error': failure.message},
        );
        if (preserveFeedback) {
          return;
        }
        emit(_buildState(isLoading: false, errorMessage: failure.message));
      },
    );
  }

  Future<void> refreshHistory() async {
    await loadHistory(showLoading: false);
  }

  Future<void> refreshHistoryQuiet() async {
    await loadHistory(showLoading: false, preserveFeedback: true);
  }

  static const int _peerHistoryPageSize = 20;

  Future<void> loadPeerConversation(String peerClientId) async {
    final peerId = peerClientId.trim();
    if (peerId.isEmpty) {
      return;
    }
    if (currentClientId == null) {
      return;
    }

    _unifiedNodeStore.ensurePeerClient(clientId: peerId);
    unawaited(_syncPeerProfiles({peerId}));

    final existing = state.peerHistory(peerId);
    if (existing.isLoadingInitial) {
      return;
    }
    if (existing.transfers.isNotEmpty) {
      final merged = _mergePeerConversationTransfers(
        existing.transfers,
        state.transfersForPeer(currentClientId!, peerId),
      );
      emit(
        _buildState(
          peerConversationHistories: _withPeerHistory(
            peerId,
            existing.copyWith(transfers: merged),
          ),
        ),
      );
      unawaited(_pullThumbnailsForPeerConversation(peerId));
      return;
    }

    emit(
      _buildState(
        peerConversationHistories: _withPeerHistory(
          peerId,
          existing.copyWith(
            isLoadingInitial: true,
            isLoadingMore: false,
          ),
        ),
      ),
    );

    final result = await _relayRepository.loadPeerHistory(
      peerClientId: peerId,
      limit: _peerHistoryPageSize,
    );
    result.when(
      success: (page) {
        final current = state.peerHistory(peerId);
        final merged = _mergePeerConversationTransfers(
          page.transfers,
          current.transfers,
        );
        emit(
          _buildState(
            peerConversationHistories: _withPeerHistory(
              peerId,
              PeerConversationHistory(
                transfers: merged,
                hasMore: page.hasMore,
              ),
            ),
          ),
        );
        unawaited(_previewCache?.pruneStale(
          page.transfers.map((transfer) => transfer.transferId).toSet(),
        ));
        unawaited(_pullThumbnailsForPeerConversation(peerId));
      },
      failure: (failure) {
        relayDiag(
          'loadPeerHistory_fail',
          fields: <String, Object?>{
            'peerId': peerId,
            'phase': 'initial',
            'error': failure.message,
          },
        );
        emit(
          _buildState(
            peerConversationHistories: _withPeerHistory(
              peerId,
              existing.copyWith(isLoadingInitial: false),
            ),
            errorMessage: failure.message,
          ),
        );
      },
    );
  }

  Future<void> loadOlderPeerMessages(String peerClientId) async {
    final peerId = peerClientId.trim();
    if (peerId.isEmpty) {
      return;
    }
    if (currentClientId == null) {
      return;
    }

    final existing = state.peerHistory(peerId);
    if (existing.isLoadingInitial ||
        existing.isLoadingMore ||
        !existing.hasMore ||
        existing.oldestCursor == null) {
      return;
    }

    emit(
      _buildState(
        peerConversationHistories: _withPeerHistory(
          peerId,
          existing.copyWith(isLoadingMore: true),
        ),
      ),
    );

    final result = await _relayRepository.loadPeerHistory(
      peerClientId: peerId,
      limit: _peerHistoryPageSize,
      beforeCreatedAt: existing.oldestCursor,
    );
    result.when(
      success: (page) {
        final merged = _mergePeerConversationTransfers(
          existing.transfers,
          page.transfers,
        );
        emit(
          _buildState(
            peerConversationHistories: _withPeerHistory(
              peerId,
              existing.copyWith(
                transfers: merged,
                hasMore: page.hasMore,
                isLoadingMore: false,
              ),
            ),
          ),
        );
        unawaited(_pullThumbnailsForPeerConversation(peerId));
      },
      failure: (failure) {
        relayDiag(
          'loadPeerHistory_fail',
          fields: <String, Object?>{
            'peerId': peerId,
            'phase': 'older',
            'error': failure.message,
          },
        );
        emit(
          _buildState(
            peerConversationHistories: _withPeerHistory(
              peerId,
              existing.copyWith(isLoadingMore: false),
            ),
            errorMessage: failure.message,
          ),
        );
      },
    );
  }

  /// Pulls remote thumbnails once for the active peer conversation.
  Future<void> refreshThumbnailsForActivePeer() async {
    await _autoDownloadThumbnails();
  }

  void scheduleRefreshThumbnailsForActivePeer() {
    _thumbnailRefreshDebounce?.cancel();
    _thumbnailRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (isClosed) {
        return;
      }
      unawaited(_autoDownloadThumbnails());
    });
  }

  void clearFeedback() {
    if (state.message == null && state.errorMessage == null) {
      return;
    }
    emit(_buildState(message: null, errorMessage: null));
  }

  void applyTransferEvent(String type, Map<String, dynamic> payload) {
    final rawTransfer = payload['transfer'];
    if (rawTransfer is! Map) {
      return;
    }
    final transferMap = rawTransfer is Map<String, dynamic>
        ? rawTransfer
        : rawTransfer.map((key, value) => MapEntry('$key', value));
    final artifact = transferMap['artifact'];
    RelayTransferEntity transfer;
    try {
      transfer = RelayTransferDto.fromJson(transferMap);
    } on FormatException catch (error) {
      relayDiag(
        'realtime_parse_fail',
        fields: <String, Object?>{
          'eventType': type,
          'transferId': transferMap['transferId'],
          'status': transferMap['status'],
          'error': error.message,
          'artifactTempPath': artifact is Map ? artifact['tempPath'] : null,
          'artifactCleanupState':
              artifact is Map ? artifact['cleanupState'] : null,
        },
      );
      return;
    }

    final nextBusyIds = Set<String>.from(state.busyTransferIds);
    final nextProgress = Map<String, double>.from(
      state.downloadProgressByTransferId,
    );
    if (type == 'transfer.completed' ||
        type == 'transfer.cancelled' ||
        type == 'transfer.failed') {
      nextBusyIds.remove(transfer.transferId);
      nextProgress.remove(transfer.transferId);
    }

    final nextTransfers = _upsertTransfer(state.transfers, transfer);
    _ingestTransferPeers(nextTransfers);
    _trackUnreadForTransferEvent(
      eventType: type,
      transfer: transfer,
    );
    emit(
      _buildState(
        transfers: nextTransfers,
        busyTransferIds: nextBusyIds,
        downloadProgressByTransferId: nextProgress,
        peerConversationHistories: _upsertPeerConversationForTransfer(
          transfer,
        ),
      ),
    );
    final selfClientId = currentClientId;
    if (selfClientId != null && transfer.isReceiver(selfClientId)) {
      unawaited(
        _pullRemoteThumbnailForTransfer(
          transfer,
          selfClientId: selfClientId,
          requireActivePeer: false,
        ).then((changed) {
          if (changed && !isClosed) {
            emit(_buildState(mediaCacheRevision: state.mediaCacheRevision + 1));
          }
        }),
      );
    }
    final activePeerId = state.activePeerClientId;
    if (selfClientId != null &&
        activePeerId != null &&
        transfer.involvesPeer(selfClientId, activePeerId)) {
      scheduleRefreshThumbnailsForActivePeer();
    }
  }

  void ingestSnapshotTransfers(List<RelayTransferEntity> transfers) {
    if (transfers.isEmpty) {
      return;
    }

    var nextTransfers = state.transfers;
    var nextPeerHistories = Map<String, PeerConversationHistory>.from(
      state.peerConversationHistories,
    );
    final selfClientId = currentClientId;
    for (final transfer in transfers) {
      nextTransfers = _upsertTransfer(nextTransfers, transfer);
      if (selfClientId == null) {
        continue;
      }
      final peerId = transfer.counterpartClientIdFor(selfClientId)?.trim();
      if (peerId == null || peerId.isEmpty) {
        continue;
      }
      if (!transfer.involvesPeer(selfClientId, peerId)) {
        continue;
      }
      final existing =
          nextPeerHistories[peerId] ?? const PeerConversationHistory();
      final merged = _upsertTransfer(existing.transfers, transfer);
      merged.sort((left, right) => left.createdAt.compareTo(right.createdAt));
      nextPeerHistories[peerId] = existing.copyWith(transfers: merged);
    }
    _ingestTransferPeers(nextTransfers);
    _recomputeUnreadFromHistory(nextTransfers);
    emit(
      _buildState(
        transfers: nextTransfers,
        peerConversationHistories: nextPeerHistories,
      ),
    );
    final activePeerId = state.activePeerClientId?.trim();
    if (activePeerId != null && activePeerId.isNotEmpty) {
      unawaited(_pullThumbnailsForPeerConversation(activePeerId));
    }
  }

  void ingestSnapshotTransferMaps(List<dynamic> rawTransfers) {
    if (rawTransfers.isEmpty) {
      return;
    }

    final transfers = <RelayTransferEntity>[];
    for (final raw in rawTransfers) {
      if (raw is! Map) {
        continue;
      }
      try {
        transfers.add(
          RelayTransferDto.fromJson(
            raw is Map<String, dynamic>
                ? raw
                : raw.map((key, value) => MapEntry('$key', value)),
          ),
        );
      } on FormatException catch (error) {
        relayDiag(
          'snapshot_parse_fail',
          fields: <String, Object?>{
            'transferId': raw['transferId'],
            'error': error.message,
          },
        );
        continue;
      }
    }
    ingestSnapshotTransfers(transfers);
  }

  void setActivePeer(String? peerClientId) {
    final normalized = peerClientId?.trim();
    final nextPeer = normalized == null || normalized.isEmpty ? null : normalized;
    if (state.activePeerClientId == nextPeer) {
      return;
    }
    emit(_buildState(activePeerClientId: nextPeer));
    if (nextPeer != null) {
      unawaited(loadPeerConversation(nextPeer));
    }
  }

  Future<void> markPeerRead(String peerClientId) async {
    final normalizedPeerId = peerClientId.trim();
    if (normalizedPeerId.isEmpty) {
      return;
    }

    final readAt = _unreadTracker.markPeerRead(normalizedPeerId);
    final storage = _relayUnreadStore;
    final scope = _unreadScope;
    if (storage != null && scope != null) {
      await storage.writeLastReadAt(
        serverId: scope.serverId,
        clientId: scope.clientId,
        peerId: normalizedPeerId,
        readAt: readAt,
      );
    }

    emit(_buildState());
  }

  RelayTransferEntity? lastIncomingTransferForPeer(String peerClientId) {
    final selfClientId = currentClientId;
    if (selfClientId == null) {
      return null;
    }

    for (final transfer in state.transfers) {
      if (!transfer.isReceiver(selfClientId)) {
        continue;
      }
      if (transfer.senderClientId != peerClientId) {
        continue;
      }
      return transfer;
    }
    return null;
  }

  Future<void> sendFilesToPeer(String peerClientId) async {
    if (state.isSending) {
      return;
    }
    final selectedPaths = await _deviceFileService.pickMultipleFiles();
    if (selectedPaths == null || selectedPaths.isEmpty) {
      return;
    }
    await sendLocalPathsToPeer(peerClientId, selectedPaths);
  }

  Future<void> sendLocalPathsToPeer(
    String peerClientId,
    List<String> localPaths, {
    Map<String, String>? mimeByPath,
  }) async {
    if (state.isSending) {
      return;
    }
    if (localPaths.isEmpty) {
      return;
    }
    if (currentClientId == null) {
      emit(_buildState(errorMessage: '当前会话缺少绑定的 deviceId，无法发起 Relay'));
      return;
    }

    _unifiedNodeStore.ensurePeerClient(clientId: peerClientId);
    emit(
      _buildState(
        isSending: true,
        sendingPeerId: peerClientId,
        message: null,
        errorMessage: null,
      ),
    );

    var successCount = 0;
    final failures = <String>[];
    var currentTransfers = state.transfers;
    for (final localPath in localPaths) {
      final fileName = await _deviceFileService.getFileName(localPath);
      final mimeType =
          mimeByPath?[localPath] ?? guessMimeTypeFromFileName(fileName);
      final result = await _relayRepository.sendFile(
        receiverClientId: peerClientId,
        localPath: localPath,
        mimeType: mimeType,
        onTransferCreated: (transfer) {
          if (isClosed) {
            return;
          }
          currentTransfers = _upsertTransfer(currentTransfers, transfer);
          emit(
            _buildState(
              transfers: currentTransfers,
              peerConversationHistories: _upsertPeerConversationTransfer(
                peerClientId,
                transfer,
              ),
            ),
          );
        },
        onUploadProgress: (transfer, sentBytes, totalBytes) {
          if (isClosed) {
            return;
          }
          currentTransfers = _upsertTransfer(currentTransfers, transfer);
          emit(
            _buildState(
              transfers: currentTransfers,
              peerConversationHistories: _upsertPeerConversationTransfer(
                peerClientId,
                transfer,
              ),
            ),
          );
        },
      );
      result.when(
        success: (transfer) {
          successCount += 1;
          currentTransfers = _upsertTransfer(currentTransfers, transfer);
          unawaited(
            _cacheSenderMedia(
              transfer: transfer,
              localPath: localPath,
              mimeType: mimeType,
            ),
          );
        },
        failure: (failure) {
          failures.add(failure.message);
        },
      );
    }

    _ingestTransferPeers(currentTransfers);
    final peerName =
        peerById(peerClientId)?.publicDisplayName ?? peerClientId;
    emit(
      _buildState(
        isSending: false,
        sendingPeerId: null,
        transfers: currentTransfers,
        peerConversationHistories: successCount > 0
            ? _appendSentTransfersToPeerConversation(
                peerClientId,
                currentTransfers,
              )
            : null,
        message: successCount > 0
            ? failures.isEmpty
                  ? '已向 $peerName 发送 $successCount 个文件'
                  : '已发送 $successCount 个文件，${failures.length} 个失败'
            : null,
        errorMessage: successCount == 0 && failures.isNotEmpty
            ? failures.first
            : null,
      ),
    );

    if (successCount > 0) {
      relayDiag(
        'refreshHistory_after_send',
        fields: <String, Object?>{
          'peerClientId': peerClientId,
          'successCount': successCount,
        },
      );
      unawaited(refreshHistoryQuiet());
    }
  }

  Future<void> _cacheSenderMedia({
    required RelayTransferEntity transfer,
    required String localPath,
    required String? mimeType,
  }) async {
    final cache = _previewCache;
    if (cache == null) {
      return;
    }
    final kind = relayMediaKindFromTransfer(transfer);
    if (kind == RelayMediaKind.other) {
      return;
    }

    await cache.putOriginal(
      transferId: transfer.transferId,
      originalPath: localPath,
      kind: kind,
    );

    var thumbPath = await _thumbnailCacheManager.buildSavePath(
      transfer.transferId,
      kind: kind,
    );
    if (!File(thumbPath).existsSync()) {
      final generated = await _thumbnailGenerator.generate(
        localPath: localPath,
        transferId: transfer.transferId,
        mimeType: mimeType,
      );
      if (generated != null && generated.isNotEmpty) {
        thumbPath = generated;
      }
    }

    if (!File(thumbPath).existsSync()) {
      return;
    }

    await cache.putThumbnail(
      transferId: transfer.transferId,
      thumbnailPath: thumbPath,
      kind: kind,
    );
    if (kind == RelayMediaKind.video && kDebugMode) {
      debugPrint(
        '[RelayThumb] SEND-CACHED transfer=${transfer.transferId} '
        'kind=video path=$thumbPath',
      );
    }
    await _persistThumbnailFile(
      transferId: transfer.transferId,
      filePath: thumbPath,
      kind: kind,
    );
  }

  Future<void> _persistThumbnailFile({
    required String transferId,
    required String filePath,
    required RelayMediaKind kind,
  }) async {
    final cache = _previewCache;
    if (cache == null) {
      return;
    }
    await _registerThumbnailAndEvict(
      transferId: transferId,
      filePath: filePath,
    );
    if (!isClosed) {
      emit(_buildState(mediaCacheRevision: state.mediaCacheRevision + 1));
    }
  }

  Future<void> _registerThumbnailAndEvict({
    required String transferId,
    required String filePath,
  }) async {
    final cache = _previewCache;
    if (cache == null) {
      return;
    }
    final evictedIds = await _thumbnailCacheManager.registerFile(
      transferId: transferId,
      filePath: filePath,
    );
    for (final evictedId in evictedIds) {
      await cache.clearThumbnail(evictedId);
    }
  }

  Future<void> _autoDownloadThumbnails() async {
    final activePeerId = state.activePeerClientId?.trim();
    if (activePeerId == null || activePeerId.isEmpty) {
      return;
    }
    await _pullThumbnailsForPeerConversation(activePeerId);
  }

  Future<bool> _isOnWifi() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.wifi);
  }

  Future<void> _pullThumbnailsForPeerConversation(String peerClientId) async {
    final cache = _previewCache;
    if (cache == null) {
      return;
    }

    final selfClientId = currentClientId;
    if (selfClientId == null) {
      return;
    }

    if (!await _isOnWifi()) {
      return;
    }

    var cacheChanged = false;
    for (final transfer in state.peerHistory(peerClientId).transfers) {
      if (!transfer.isReceiver(selfClientId)) {
        continue;
      }
      if (await _pullRemoteThumbnailForTransfer(
        transfer,
        selfClientId: selfClientId,
        activePeerId: peerClientId,
        requireActivePeer: true,
      )) {
        cacheChanged = true;
      }
    }

    if (cacheChanged && !isClosed) {
      emit(_buildState(mediaCacheRevision: state.mediaCacheRevision + 1));
    }
  }

  Future<bool> _pullRemoteThumbnailForTransfer(
    RelayTransferEntity transfer, {
    String? activePeerId,
    String? selfClientId,
    bool requireActivePeer = true,
  }) async {
    final cache = _previewCache;
    final resolvedSelfClientId = selfClientId ?? currentClientId;
    final resolvedActivePeerId =
        activePeerId ?? state.activePeerClientId?.trim();
    if (cache == null || resolvedSelfClientId == null) {
      return false;
    }
    if (requireActivePeer) {
      if (resolvedActivePeerId == null || resolvedActivePeerId.isEmpty) {
        return false;
      }
      if (!transfer.involvesPeer(resolvedSelfClientId, resolvedActivePeerId)) {
        return false;
      }
    }
    if (!transfer.isReceiver(resolvedSelfClientId)) {
      return false;
    }
    final kind = relayMediaKindFromTransfer(transfer);
    if (kind == RelayMediaKind.other) {
      return false;
    }
    if (cache.thumbnailPathFor(transfer.transferId) != null) {
      return false;
    }
    if (!relayTransferCanFetchRemoteThumbnail(transfer)) {
      return false;
    }

    final savePath = await _thumbnailCacheManager.buildSavePath(
      transfer.transferId,
      kind: kind,
    );
    final result = await _relayRepository.downloadThumbnailForTransfer(
      transfer: transfer,
      savePath: savePath,
    );
    final localPath = result.dataOrNull;
    if (localPath == null || !File(localPath).existsSync()) {
      if (kDebugMode) {
        final kind = relayMediaKindFromTransfer(transfer);
        debugPrint(
          '[RelayThumb] RECV-CACHE-FAIL transfer=${transfer.transferId} '
          'kind=${kind.name} status=${transfer.status.name} — download returned null or file missing',
        );
      }
      return false;
    }
    await cache.putThumbnail(
      transferId: transfer.transferId,
      thumbnailPath: localPath,
      kind: kind,
    );
    await _registerThumbnailAndEvict(
      transferId: transfer.transferId,
      filePath: localPath,
    );
    return true;
  }

  /// Downloads the transfer when needed and returns the local original path.
  Future<String?> downloadTransferForPreview(
    RelayTransferEntity transfer,
  ) async {
    final existing = _previewCache?.originalPathFor(transfer.transferId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final transferId = transfer.transferId;
    if (state.busyTransferIds.contains(transferId)) {
      return null;
    }

    if (transfer.status != RelayTransferStatus.ready) {
      emit(
        _buildState(
          errorMessage: '文件尚未发送完成，请稍后再试',
        ),
      );
      return null;
    }

    relayDiag(
      'downloadForPreview_start',
      fields: <String, Object?>{
        'transferId': transferId,
        'status': transfer.status.name,
        'cleanupState': transfer.artifact.cleanupState.name,
      },
    );

    emit(
      _buildState(
        busyTransferIds: {...state.busyTransferIds, transferId},
        downloadProgressByTransferId: <String, double>{
          ...state.downloadProgressByTransferId,
          transferId: 0,
        },
        message: null,
        errorMessage: null,
      ),
    );

    final result = await _relayRepository.downloadTransfer(
      transfer: transfer,
      onProgress: (receivedBytes, totalBytes) {
        if (isClosed) {
          return;
        }
        final progress = totalBytes <= 0 ? 0 : receivedBytes / totalBytes;
        emit(
          _buildState(
            downloadProgressByTransferId: <String, double>{
              ...state.downloadProgressByTransferId,
              transferId: progress.clamp(0.0, 1.0).toDouble(),
            },
          ),
        );
      },
    );

    String? originalPath;
    if (result.isSuccess) {
      final downloadResult = result.dataOrNull!;
      if (downloadResult.localPath != null) {
        originalPath = downloadResult.localPath;
        await _previewCache?.putOriginal(
          transferId: transferId,
          originalPath: downloadResult.localPath!,
          kind: relayMediaKindFromTransfer(transfer),
          isContentUri: true,
        );
      }
      emit(
        _buildState(
          busyTransferIds: _withoutBusyId(transferId),
          downloadProgressByTransferId: _withoutProgress(transferId),
          message: '${downloadResult.fileName} 已保存到系统目录',
          mediaCacheRevision: state.mediaCacheRevision + 1,
        ),
      );
      relayDiag('refreshHistory_after_download', fields: {'transferId': transferId});
      unawaited(refreshHistoryQuiet());
      return originalPath;
    }

    relayDiag(
      'downloadForPreview_fail',
      fields: <String, Object?>{
        'transferId': transferId,
        'error': result.failureOrNull?.message,
      },
    );
    emit(
      _buildState(
        busyTransferIds: _withoutBusyId(transferId),
        downloadProgressByTransferId: _withoutProgress(transferId),
        errorMessage: result.failureOrNull?.message ?? '下载失败',
      ),
    );
    return null;
  }

  Future<void> downloadAndPreviewTransfer(RelayTransferEntity transfer) async {
    await downloadTransferForPreview(transfer);
  }

  Future<void> downloadTransfer(RelayTransferEntity transfer) async {
    await downloadTransferForPreview(transfer);
  }

  Future<void> cancelTransfer(String transferId) async {
    if (state.busyTransferIds.contains(transferId)) {
      return;
    }
    emit(
      _buildState(
        busyTransferIds: {...state.busyTransferIds, transferId},
        message: null,
        errorMessage: null,
      ),
    );

    final result = await _relayRepository.cancelTransfer(
      transferId: transferId,
    );
    result.when(
      success: (transfer) {
        emit(
          _buildState(
            transfers: _upsertTransfer(state.transfers, transfer),
            busyTransferIds: _withoutBusyId(transferId),
            message: '已取消传输',
          ),
        );
      },
      failure: (failure) {
        emit(
          _buildState(
            busyTransferIds: _withoutBusyId(transferId),
            errorMessage: failure.message,
          ),
        );
      },
    );
  }

  Future<void> retryTransfer(String transferId) async {
    if (state.busyTransferIds.contains(transferId)) {
      return;
    }
    emit(
      _buildState(
        busyTransferIds: {...state.busyTransferIds, transferId},
        message: null,
        errorMessage: null,
      ),
    );

    final result = await _relayRepository.retryTransfer(transferId: transferId);
    result.when(
      success: (transfer) {
        emit(
          _buildState(
            transfers: _upsertTransfer(state.transfers, transfer),
            busyTransferIds: _withoutBusyId(transferId),
            message: '已创建重试传输',
          ),
        );
      },
      failure: (failure) {
        emit(
          _buildState(
            busyTransferIds: _withoutBusyId(transferId),
            errorMessage: failure.message,
          ),
        );
      },
    );
  }

  RelayState _buildState({
    bool? isLoading,
    bool? isSending,
    Object? sendingPeerId = _unset,
    List<RelayTransferEntity>? transfers,
    Map<String, PeerConversationHistory>? peerConversationHistories,
    Set<String>? busyTransferIds,
    Map<String, double>? downloadProgressByTransferId,
    Object? activePeerClientId = _unset,
    int? mediaCacheRevision,
    Object? message = _unset,
    Object? errorMessage = _unset,
  }) {
    final effectiveTransfers = List<RelayTransferEntity>.unmodifiable(
      _sortTransfers(transfers ?? state.transfers),
    );
    final effectiveBusyIds = Set<String>.unmodifiable(
      busyTransferIds ?? state.busyTransferIds,
    );
    final effectiveProgress = Map<String, double>.unmodifiable(
      downloadProgressByTransferId ?? state.downloadProgressByTransferId,
    );
    return state.copyWith(
      isLoading: isLoading ?? state.isLoading,
      isSending: isSending ?? state.isSending,
      sendingPeerId: sendingPeerId,
      transfers: effectiveTransfers,
      peerConversationHistories:
          peerConversationHistories ?? state.peerConversationHistories,
      busyTransferIds: effectiveBusyIds,
      downloadProgressByTransferId: effectiveProgress,
      unreadCountByPeerId: _unreadTracker.unreadCountByPeerId,
      activePeerClientId: activePeerClientId,
      mediaCacheRevision: mediaCacheRevision,
      message: message,
      errorMessage: errorMessage,
    );
  }

  void _trackUnreadForTransferEvent({
    required String eventType,
    required RelayTransferEntity transfer,
  }) {
    final selfClientId = currentClientId;
    if (selfClientId == null) {
      return;
    }

    _unreadTracker.onTransferEvent(
      eventType: eventType,
      transfer: transfer,
      myClientId: selfClientId,
      activePeerClientId: state.activePeerClientId,
    );
  }

  void _recomputeUnreadFromHistory(List<RelayTransferEntity> transfers) {
    final selfClientId = currentClientId;
    if (selfClientId == null) {
      _unreadTracker.clear();
      return;
    }

    final scope = _unreadScope;
    final storage = _relayUnreadStore;
    if (storage != null && scope != null) {
      final lastReadAtByPeerId = <String, DateTime>{};
      final peerIds = <String>{};
      for (final transfer in transfers) {
        if (!transfer.isReceiver(selfClientId)) {
          continue;
        }
        final peerId = transfer.senderClientId.trim();
        if (peerId.isNotEmpty && peerId != selfClientId) {
          peerIds.add(peerId);
        }
      }
      for (final peerId in peerIds) {
        final lastReadAt = storage.readLastReadAt(
          serverId: scope.serverId,
          clientId: scope.clientId,
          peerId: peerId,
        );
        if (lastReadAt != null) {
          lastReadAtByPeerId[peerId] = lastReadAt;
        }
      }
      _unreadTracker.seedLastReadAt(lastReadAtByPeerId);
    }

    _unreadTracker.recomputeFromHistory(
      transfers: transfers,
      myClientId: selfClientId,
    );
  }

  ({String serverId, String clientId})? get _unreadScope {
    final serverId =
        _unifiedNodeStore.currentServer?.identity.serverId?.trim();
    final clientId = currentClientId;
    if (serverId == null ||
        serverId.isEmpty ||
        clientId == null ||
        clientId.isEmpty) {
      return null;
    }
    return (serverId: serverId, clientId: clientId);
  }

  List<RelayTransferEntity> _sortTransfers(
    List<RelayTransferEntity> transfers,
  ) {
    final sorted = List<RelayTransferEntity>.from(transfers);
    sorted.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  List<RelayTransferEntity> _mergePeerConversationTransfers(
    List<RelayTransferEntity> existingAsc,
    List<RelayTransferEntity> incomingAsc,
  ) {
    final byId = <String, RelayTransferEntity>{
      for (final transfer in existingAsc) transfer.transferId: transfer,
    };
    for (final transfer in incomingAsc) {
      byId[transfer.transferId] = byId.containsKey(transfer.transferId)
          ? mergeRelayTransferEntity(byId[transfer.transferId]!, transfer)
          : transfer;
    }
    final merged = byId.values.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return merged;
  }

  Map<String, PeerConversationHistory> _withPeerHistory(
    String peerId,
    PeerConversationHistory history,
  ) {
    return <String, PeerConversationHistory>{
      ...state.peerConversationHistories,
      peerId: history,
    };
  }

  Map<String, PeerConversationHistory>? _upsertPeerConversationTransfer(
    String peerId,
    RelayTransferEntity transfer,
  ) {
    final selfClientId = currentClientId;
    if (selfClientId == null ||
        !transfer.involvesPeer(selfClientId, peerId.trim())) {
      return null;
    }

    final existing = state.peerHistory(peerId);
    final merged = _upsertTransfer(existing.transfers, transfer);
    merged.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return _withPeerHistory(
      peerId,
      existing.copyWith(transfers: merged),
    );
  }

  Map<String, PeerConversationHistory>? _upsertPeerConversationForTransfer(
    RelayTransferEntity transfer,
  ) {
    final selfClientId = currentClientId;
    if (selfClientId == null) {
      return null;
    }

    final peerId = transfer.counterpartClientIdFor(selfClientId)?.trim();
    if (peerId == null || peerId.isEmpty) {
      return null;
    }

    return _upsertPeerConversationTransfer(peerId, transfer);
  }

  Map<String, PeerConversationHistory>? _appendSentTransfersToPeerConversation(
    String peerClientId,
    List<RelayTransferEntity> allTransfers,
  ) {
    final selfClientId = currentClientId;
    if (selfClientId == null) {
      return null;
    }

    final peerId = peerClientId.trim();
    final existing = state.peerHistory(peerId);
    final peerTransfers = allTransfers
        .where((transfer) => transfer.involvesPeer(selfClientId, peerId))
        .toList(growable: false);
    if (peerTransfers.isEmpty) {
      return null;
    }

    final merged = _mergePeerConversationTransfers(
      existing.transfers,
      peerTransfers,
    );
    return _withPeerHistory(
      peerId,
      existing.copyWith(transfers: merged),
    );
  }

  List<RelayTransferEntity> _mergeTransfersWithExisting(
    List<RelayTransferEntity> incoming,
  ) {
    final existingById = <String, RelayTransferEntity>{
      for (final transfer in state.transfers) transfer.transferId: transfer,
    };
    return incoming
        .map((transfer) {
          final existing = existingById[transfer.transferId];
          if (existing == null) {
            return transfer;
          }
          return mergeRelayTransferEntity(existing, transfer);
        })
        .toList(growable: false);
  }

  List<RelayTransferEntity> _upsertTransfer(
    List<RelayTransferEntity> transfers,
    RelayTransferEntity transfer,
  ) {
    final next = <RelayTransferEntity>[];
    var replaced = false;
    for (final item in transfers) {
      if (item.transferId == transfer.transferId) {
        next.add(mergeRelayTransferEntity(item, transfer));
        replaced = true;
      } else {
        next.add(item);
      }
    }
    if (!replaced) {
      next.add(transfer);
    }
    return next;
  }

  void _ingestTransferPeers(List<RelayTransferEntity> transfers) {
    final selfClientId = currentClientId;
    final peerIds = <String>{};
    for (final transfer in transfers) {
      final peerClientId = selfClientId == null
          ? null
          : transfer.counterpartClientIdFor(selfClientId);
      if (peerClientId == null || peerClientId == selfClientId) {
        continue;
      }
      peerIds.add(peerClientId);
      _unifiedNodeStore.ensurePeerClient(clientId: peerClientId);
    }
    unawaited(_syncPeerProfiles(peerIds));
  }

  Future<void> _syncPeerProfiles(Set<String> peerIds) async {
    final syncService = _deviceProfileSyncService;
    if (syncService == null || peerIds.isEmpty) {
      return;
    }
    await syncService.syncPeers(peerIds);
  }

  List<UnifiedNode> _buildPeers(List<RelayTransferEntity> transfers) {
    final selfClientId = currentClientId;
    final lastTransferAtByClientId = <String, DateTime>{};
    for (final transfer in transfers) {
      final peerClientId = selfClientId == null
          ? null
          : transfer.counterpartClientIdFor(selfClientId);
      if (peerClientId == null || peerClientId == selfClientId) {
        continue;
      }
      final previous = lastTransferAtByClientId[peerClientId];
      if (previous == null || transfer.updatedAt.isAfter(previous)) {
        lastTransferAtByClientId[peerClientId] = transfer.updatedAt;
      }
    }

    final peerList = _unifiedNodeStore.peerClients.toList(growable: false)
      ..sort((left, right) {
        final leftOnline = left.presence.status == PresenceStatus.online;
        final rightOnline = right.presence.status == PresenceStatus.online;
        if (leftOnline != rightOnline) {
          return leftOnline ? -1 : 1;
        }
        final leftClientId = left.identity.clientId;
        final rightClientId = right.identity.clientId;
        final leftAt = leftClientId == null
            ? null
            : lastTransferAtByClientId[leftClientId];
        final rightAt = rightClientId == null
            ? null
            : lastTransferAtByClientId[rightClientId];
        if (leftAt != null && rightAt != null) {
          final compare = rightAt.compareTo(leftAt);
          if (compare != 0) {
            return compare;
          }
        } else if (leftAt != null) {
          return -1;
        } else if (rightAt != null) {
          return 1;
        }
        return left.publicDisplayName.compareTo(right.publicDisplayName);
      });
    return peerList;
  }

  Set<String> _withoutBusyId(String transferId) {
    final next = Set<String>.from(state.busyTransferIds);
    next.remove(transferId);
    return next;
  }

  Map<String, double> _withoutProgress(String transferId) {
    final next = Map<String, double>.from(state.downloadProgressByTransferId);
    next.remove(transferId);
    return next;
  }

  @override
  Future<void> close() async {
    _thumbnailRefreshDebounce?.cancel();
    await _nodeStoreSubscription.cancel();
    await super.close();
  }
}

const Object _unset = Object();
