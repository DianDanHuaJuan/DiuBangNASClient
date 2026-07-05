/// 文件输入：FileBrowserCubit 状态
/// 文件职责：显示文件浏览页面，支持顶级目录切换、分类过滤，使用 SliverGrid 实现懒加载
/// 文件对外接口：FileBrowserPage
/// 文件包含：FileBrowserPage
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/service_locator.dart';
import '../../../../core/image/image_cache_key_builder.dart';
import '../../../../core/path/nas_path.dart';
import '../../../preview/presentation/pages/gallery_page.dart';
import '../../../transfer/domain/entities/transfer_direction.dart';
import '../../../transfer/domain/entities/transfer_status.dart';
import '../../../transfer/domain/entities/transfer_task_entity.dart';
import '../../../transfer/presentation/cubit/transfer_cubit.dart';
import '../../../transfer/presentation/cubit/transfer_state.dart';
import '../../../transfer/presentation/utils/queue_upload_to_server_directory.dart';
import '../../../transfer/presentation/widgets/upload_conflict_dialog.dart';
import '../../domain/entities/file_category.dart';
import '../../domain/entities/file_entry_entity.dart';
import '../cubit/file_browser_cubit.dart';
import '../cubit/file_browser_state.dart';
import '../widgets/file_browser_floating_actions_widget.dart';
import '../widgets/file_list_view.dart';
import '../widgets/non_preview_file_action_dialog.dart';
import '../widgets/path_breadcrumb.dart';
import '../widgets/file_category_filter.dart';

class FileBrowserPage extends StatefulWidget {
  final double bottomPadding;

  const FileBrowserPage({super.key, this.bottomPadding = 24});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  static const _queueUploadToServerDirectory = QueueUploadToServerDirectory();
  static const double _selectionActionBarHeight = 52;
  final ScrollController _scrollController = ScrollController();
  static const int _crossAxisCount = 4;
  static const double _gridPadding = 24.0;
  static const double _headerHeight = 250.0;
  static const int _preloadRows = 2;
  static const Duration _scrollSettleDelay = Duration(milliseconds: 72);
  double _lastScrollOffset = 0;
  bool _isScrollActive = false;
  bool _pendingLoadMore = false;
  bool _lastPreloadEnabled = true;
  Timer? _scrollSettleTimer;

  int _lastVisibleStartIndex = -1;
  int _lastVisibleEndIndex = -1;
  int _lastFocusedStartIndex = -1;
  int _lastFocusedEndIndex = -1;
  final Map<String, _TrackedUploadTask> _trackedUploadTasks = {};
  int _completedTrackedUploadCount = 0;
  int _skippedTrackedUploadCount = 0;
  int _failedTrackedUploadCount = 0;
  String? _activeConflictTaskId;
  bool _isDragSelecting = false;
  String? _lastDragToggledPath;
  bool _uploadRefreshPending = false;
  NasPath? _lastThumbnailNavigationPath;
  String? _lastThumbnailRootId;
  FileCategory? _lastThumbnailCategory;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollSettleTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _syncVisibleThumbnailRange();
    _maybeLoadMore();
    if (_scrollController.hasClients) {
      _lastScrollOffset = _scrollController.offset;
    }
  }

  void _resetVisibleRangeTracking() {
    _lastVisibleStartIndex = -1;
    _lastVisibleEndIndex = -1;
    _lastFocusedStartIndex = -1;
    _lastFocusedEndIndex = -1;
    _lastPreloadEnabled = true;
  }

  void _scheduleVisibleThumbnailRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncVisibleThumbnailRange();
      _maybeLoadMore(force: true);
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      _markScrollActive();
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        _scheduleSettledScrollWork();
      } else {
        _markScrollActive();
      }
      return false;
    }
    if (notification is ScrollEndNotification) {
      _scheduleSettledScrollWork();
    }
    return false;
  }

  void _markScrollActive() {
    _scrollSettleTimer?.cancel();
    if (_isScrollActive) {
      return;
    }
    setState(() {
      _isScrollActive = true;
    });
  }

  void _scheduleSettledScrollWork() {
    _scrollSettleTimer?.cancel();
    _scrollSettleTimer = Timer(_scrollSettleDelay, () {
      if (!mounted) {
        return;
      }
      if (_isScrollActive) {
        setState(() {
          _isScrollActive = false;
        });
      }
      _syncVisibleThumbnailRange();
      _maybeLoadMore(force: true);
    });
  }

  void _maybeLoadMore({bool force = false}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final shouldLoadMore = _scrollController.position.extentAfter < 800;
    if (!shouldLoadMore) {
      _pendingLoadMore = false;
      return;
    }
    if (_isScrollActive && !force) {
      _pendingLoadMore = true;
      return;
    }
    if (_pendingLoadMore || shouldLoadMore) {
      _pendingLoadMore = false;
      context.read<FileBrowserCubit>().loadMore();
    }
  }

  ScrollPhysics? _resolveScrollPhysics(FileBrowserState state) {
    if (state is! FileBrowserLoaded) {
      return const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      );
    }
    if (state.filteredFiles.length <= 12) {
      return const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      );
    }
    return null;
  }

  void _syncVisibleThumbnailRange() {
    final cubit = context.read<FileBrowserCubit>();
    final state = cubit.state;
    if (state is! FileBrowserLoaded) return;
    if (!_scrollController.hasClients) return;

    final mediaFiles = state.mediaFiles;

    if (mediaFiles.isEmpty) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = screenWidth - (_gridPadding * 2);
    final itemWidth = gridWidth / _crossAxisCount;
    final rowHeight = itemWidth + 4;

    final scrollOffset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;
    if (viewportHeight <= 0) return;

    final firstVisibleRow = ((scrollOffset - _headerHeight) / rowHeight)
        .floor();
    final lastVisibleRow =
        ((scrollOffset + viewportHeight - _headerHeight) / rowHeight).floor();
    final visibleStartIndex = (firstVisibleRow * _crossAxisCount).clamp(
      0,
      mediaFiles.length,
    );
    final visibleEndIndex = ((lastVisibleRow + 1) * _crossAxisCount).clamp(
      0,
      mediaFiles.length,
    );

    final startIndex = ((firstVisibleRow - _preloadRows) * _crossAxisCount)
        .clamp(0, mediaFiles.length);
    final endIndex = ((lastVisibleRow + _preloadRows + 1) * _crossAxisCount)
        .clamp(0, mediaFiles.length);

    if (startIndex == _lastVisibleStartIndex &&
        endIndex == _lastVisibleEndIndex &&
        visibleStartIndex == _lastFocusedStartIndex &&
        visibleEndIndex == _lastFocusedEndIndex &&
        _lastPreloadEnabled == !_isScrollActive) {
      return;
    }

    _lastVisibleStartIndex = startIndex;
    _lastVisibleEndIndex = endIndex;
    _lastFocusedStartIndex = visibleStartIndex;
    _lastFocusedEndIndex = visibleEndIndex;
    _lastPreloadEnabled = !_isScrollActive;

    cubit.requestThumbnails(
      visibleStartIndex: visibleStartIndex,
      visibleEndIndex: visibleEndIndex,
      preloadStartIndex: startIndex,
      preloadEndIndex: endIndex,
      allowPreload: !_isScrollActive,
      scrollDirection: _resolveScrollDirection(scrollOffset),
    );
  }

  ScrollDirection _resolveScrollDirection(double currentOffset) {
    if (currentOffset > _lastScrollOffset) {
      return ScrollDirection.forward;
    }
    if (currentOffset < _lastScrollOffset) {
      return ScrollDirection.reverse;
    }
    return ScrollDirection.idle;
  }

  Future<void> _refresh(BuildContext context, FileBrowserState state) async {
    final cubit = context.read<FileBrowserCubit>();
    if (state is FileBrowserLoaded) {
      await cubit.refreshDirectoryEntries(state.currentPath);
      return;
    }
    await cubit.loadRoot();
  }

  void _showPreviewDialog(
    BuildContext context,
    FileEntryEntity file,
    FileBrowserLoaded state,
  ) {
    final mediaFiles = state.mediaFiles;

    if (mediaFiles.isEmpty) return;

    final initialIndex = mediaFiles.indexWhere((f) => f.path == file.path);
    if (initialIndex == -1) return;

    final cubit = context.read<FileBrowserCubit>();
    final thumbnails = <String, Uint8List>{};
    for (final f in mediaFiles) {
      final data = cubit.getThumbnail(f.path);
      if (data != null) {
        thumbnails[f.path] = data;
      }
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            opaque: false,
            transitionDuration: const Duration(milliseconds: 180),
            reverseTransitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (context, animation, secondaryAnimation) {
              return GalleryPage(
                mediaFiles: mediaFiles,
                initialIndex: initialIndex,
                rootId: state.currentRootId,
                thumbnails: thumbnails,
              );
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOut,
                    ),
                    child: child,
                  );
                },
          ),
        )
        .then((_) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        });
  }

  void _showNonPreviewDownloadDialog(
    BuildContext context,
    FileEntryEntity file,
    String rootId,
  ) {
    unawaited(
      showNonPreviewFileActionDialog(
        context: context,
        file: file,
        mode: NonPreviewFileDialogMode.download,
        rootId: rootId,
      ),
    );
  }

  void _showNonPreviewDeleteDialog(
    BuildContext context,
    FileEntryEntity file,
  ) {
    unawaited(
      showNonPreviewFileActionDialog(
        context: context,
        file: file,
        mode: NonPreviewFileDialogMode.delete,
        rootId: context.read<FileBrowserCubit>().currentRootId,
        onDeleteConfirmed: () {
          context.read<FileBrowserCubit>().deleteFile(file.path);
        },
      ),
    );
  }

  Future<void> _confirmBatchDelete(
    BuildContext context,
    FileBrowserLoaded state,
  ) async {
    final cubit = context.read<FileBrowserCubit>();
    final selectedCount = state.selectedPaths.length;
    if (selectedCount == 0) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除已选中的 $selectedCount 个文件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB64848),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final paths = state.selectedPaths
        .map((path) => NasPath(rootId: state.currentRootId, path: path))
        .toList(growable: false);
    await cubit.batchDelete(paths);
  }

  double _selectionActionBarBottomOffset(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final offset = widget.bottomPadding - 40;
    final clampedOffset = offset < 24 ? 24.0 : offset;
    return safeBottom + clampedOffset;
  }

  Future<void> _pickAndUploadMedia(
    BuildContext context,
    FileBrowserCubit cubit,
  ) async {
    await _queueUploadFromPicker(
      context,
      cubit,
      pickerFailureMessage: '打开图库失败',
      pick: (context, transferCubit, targetPath) =>
          _queueUploadToServerDirectory(
            context,
            transferCubit: transferCubit,
            targetPath: targetPath,
          ),
    );
  }

  Future<void> _pickAndUploadFiles(
    BuildContext context,
    FileBrowserCubit cubit,
  ) async {
    await _queueUploadFromPicker(
      context,
      cubit,
      pickerFailureMessage: '打开文件选择器失败',
      pick: (context, transferCubit, targetPath) =>
          _queueUploadToServerDirectory.pickFilesAndQueue(
            context,
            transferCubit: transferCubit,
            targetPath: targetPath,
          ),
    );
  }

  Future<void> _queueUploadFromPicker(
    BuildContext context,
    FileBrowserCubit cubit, {
    required String pickerFailureMessage,
    required Future<QueuedServerUploadResult?> Function(
      BuildContext context,
      TransferCubit transferCubit,
      NasPath targetPath,
    )
    pick,
  }) async {
    try {
      final state = cubit.state;
      if (state is! FileBrowserLoaded) {
        return;
      }

      if (!state.currentRootWritable) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('当前目录不支持上传')));
        }
        return;
      }

      final transferCubit = context.read<TransferCubit>();
      final targetRootId = state.currentRootId;
      final targetPath = state.currentPath;
      final result = await pick(context, transferCubit, targetPath);
      if (!context.mounted || result == null) {
        return;
      }

      _handleQueuedUploadResult(
        context,
        transferCubit: transferCubit,
        targetRootId: targetRootId,
        targetPath: targetPath,
        result: result,
      );
    } catch (e) {
      if (context.mounted) {
        final message = _uploadPickerFailureMessage(
          pickerFailureMessage: pickerFailureMessage,
          error: e,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  String _uploadPickerFailureMessage({
    required String pickerFailureMessage,
    required Object error,
  }) {
    final text = error.toString();
    if (text.contains('illegal percent encoding in URI') ||
        text.contains('percent encoding in URI')) {
      return '当前目录路径包含特殊字符，请返回上级目录后重试';
    }
    return '$pickerFailureMessage: $error';
  }

  void _handleQueuedUploadResult(
    BuildContext context, {
    required TransferCubit transferCubit,
    required String targetRootId,
    required NasPath targetPath,
    required QueuedServerUploadResult result,
  }) {
    for (final task in result.createdTasks) {
      _trackedUploadTasks[task.id] = _TrackedUploadTask(
        rootId: targetRootId,
        directoryPath: targetPath.path,
      );
      if (task.status == TransferStatus.awaitingConflictResolution) {
        unawaited(_promptTrackedUploadConflict(context, task));
      }
    }

    _handleTransferStateChanged(context, transferCubit.state);
    showQueuedUploadResultSnackBar(context, result: result);
  }

  _ActiveUploadOverlay? _resolveActiveUploadOverlay(TransferState state) {
    if (state is! TransferLoaded) {
      return null;
    }

    final uploadTasks = state.tasks
        .where((task) => task.direction == TransferDirection.upload)
        .toList();

    TransferTaskEntity? currentTask;
    for (final task in uploadTasks) {
      if (task.status == TransferStatus.transferring) {
        currentTask = task;
        break;
      }
    }

    if (currentTask == null) {
      for (final task in uploadTasks) {
        if (task.status == TransferStatus.pending) {
          currentTask = task;
          break;
        }
      }
    }

    if (currentTask == null) {
      return null;
    }

    return _ActiveUploadOverlay(
      fileName: currentTask.fileName,
      progress: currentTask.progress,
    );
  }

  void _handleTransferStateChanged(
    BuildContext context,
    TransferState transferState,
  ) {
    if (transferState is! TransferLoaded) {
      return;
    }

    if (_trackedUploadTasks.isNotEmpty) {
      _handleTrackedUploadStateChanged(context, transferState);
    }
  }

  void _handleTrackedUploadStateChanged(
    BuildContext context,
    TransferLoaded transferState,
  ) {
    final fileState = context.read<FileBrowserCubit>().state;
    FileBrowserLoaded? refreshTarget;

    for (final entry in _trackedUploadTasks.entries.toList()) {
      final task = _findTaskById(transferState.tasks, entry.key);
      if (task == null) {
        continue;
      }

      if (task.status == TransferStatus.completed) {
        _completedTrackedUploadCount += 1;
        _trackedUploadTasks.remove(entry.key);
        if (fileState is FileBrowserLoaded &&
            fileState.currentRootId == entry.value.rootId &&
            fileState.currentPath.path == entry.value.directoryPath) {
          _uploadRefreshPending = true;
          refreshTarget = fileState;
        }
      } else if (task.status == TransferStatus.skipped) {
        _skippedTrackedUploadCount += 1;
        _trackedUploadTasks.remove(entry.key);
      } else if (task.status == TransferStatus.awaitingConflictResolution) {
        unawaited(_promptTrackedUploadConflict(context, task));
      } else if (task.status == TransferStatus.failed) {
        _failedTrackedUploadCount += 1;
        final err = task.errorMessage;
        if (err != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('上传失败: $err')));
        }
        _trackedUploadTasks.remove(entry.key);
      }
    }

    if (_trackedUploadTasks.isEmpty && _uploadRefreshPending) {
      _uploadRefreshPending = false;
      if (refreshTarget != null) {
        unawaited(
          context.read<FileBrowserCubit>().refreshDirectoryEntries(
            refreshTarget.currentPath,
          ),
        );
      }
    }

    if (_trackedUploadTasks.isEmpty &&
        (_completedTrackedUploadCount > 0 ||
            _skippedTrackedUploadCount > 0 ||
            _failedTrackedUploadCount > 0)) {
      _showUploadSummary(context);
    }
  }

  Future<void> _promptTrackedUploadConflict(
    BuildContext context,
    TransferTaskEntity task,
  ) async {
    if (!context.mounted) {
      return;
    }
    if (_activeConflictTaskId != null) {
      return;
    }

    _activeConflictTaskId = task.id;
    try {
      final resolution = await showUploadConflictDialog(
        context,
        fileName: task.fileName,
      );
      if (!context.mounted || resolution == null) {
        return;
      }
      await context.read<TransferCubit>().resolveUploadConflict(
        taskId: task.id,
        resolution: resolution,
      );
    } finally {
      _activeConflictTaskId = null;
    }
  }

  TransferTaskEntity? _findTaskById(
    List<TransferTaskEntity> tasks,
    String taskId,
  ) {
    for (final task in tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  void _showUploadSummary(BuildContext context) {
    if (!context.mounted) {
      return;
    }

    final message = switch ((
      _completedTrackedUploadCount,
      _skippedTrackedUploadCount,
      _failedTrackedUploadCount,
    )) {
      (final completed, 0, 0) when completed == 1 => '上传完成',
      (final completed, 0, 0) => '已完成 $completed 个上传任务',
      (0, final skipped, 0) => '已跳过 $skipped 个重名文件',
      (0, 0, final failed) => '$failed 个上传任务失败',
      (final completed, final skipped, 0) => '已完成 $completed 个，跳过 $skipped 个',
      (final completed, 0, final failed) => '已完成 $completed 个，失败 $failed 个',
      (0, final skipped, final failed) => '已跳过 $skipped 个，失败 $failed 个',
      (final completed, final skipped, final failed) =>
        '已完成 $completed 个，跳过 $skipped 个，失败 $failed 个',
    };

    _completedTrackedUploadCount = 0;
    _skippedTrackedUploadCount = 0;
    _failedTrackedUploadCount = 0;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDragSelecting) {
      return;
    }

    final result = HitTestResult();
    final viewId = View.of(context).viewId;
    WidgetsBinding.instance.hitTestInView(result, event.position, viewId);

    String? hitPath;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData) {
        final meta = target.metaData;
        if (meta is String) {
          hitPath = meta;
          break;
        }
      }
    }

    if (hitPath != null && hitPath != _lastDragToggledPath) {
      _lastDragToggledPath = hitPath;
      final currentState = context.read<FileBrowserCubit>().state;
      if (currentState is FileBrowserLoaded &&
          !currentState.selectedPaths.contains(hitPath)) {
        context.read<FileBrowserCubit>().toggleSelection(hitPath);
      }
    }
  }

  bool _isMobileServer() {
    final platform = ServiceLocator().currentSession.serverPlatform;
    return platform == 'android' || platform == 'ios';
  }

  void _handlePointerUp(PointerEvent event) {
    _isDragSelecting = false;
    _lastDragToggledPath = null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FileBrowserCubit, FileBrowserState>(
      buildWhen: (previous, current) {
        if (previous is FileBrowserLoaded && current is FileBrowserLoaded) {
          return previous.currentPath != current.currentPath ||
              previous.currentRootId != current.currentRootId ||
              previous.currentCategory != current.currentCategory ||
              previous.currentRootWritable != current.currentRootWritable ||
              previous.hasMore != current.hasMore ||
              previous.isLoadingMore != current.isLoadingMore ||
              previous.message != current.message ||
              previous.selectionMode != current.selectionMode ||
              !setEquals(previous.selectedPaths, current.selectedPaths) ||
              !identical(previous.filteredFiles, current.filteredFiles);
        }
        return previous.runtimeType != current.runtimeType;
      },
      listenWhen: (previous, current) {
        if (current is FileBrowserLoaded &&
            current.message != null &&
            current.message!.trim().isNotEmpty &&
            (previous is! FileBrowserLoaded ||
                previous.message != current.message)) {
          return true;
        }
        if (current is! FileBrowserLoaded) {
          return false;
        }
        if (previous is! FileBrowserLoaded) {
          return true;
        }
        return previous.currentPath != current.currentPath ||
            previous.currentRootId != current.currentRootId ||
            previous.currentCategory != current.currentCategory ||
            !identical(previous.filteredFiles, current.filteredFiles);
      },
      listener: (context, state) {
        if (state is FileBrowserLoaded &&
            state.message != null &&
            state.message!.trim().isNotEmpty) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(content: Text(state.message!)));
        }
        if (state is! FileBrowserLoaded) {
          return;
        }
        final navigationChanged =
            _lastThumbnailNavigationPath != state.currentPath ||
            _lastThumbnailRootId != state.currentRootId ||
            _lastThumbnailCategory != state.currentCategory;
        _lastThumbnailNavigationPath = state.currentPath;
        _lastThumbnailRootId = state.currentRootId;
        _lastThumbnailCategory = state.currentCategory;
        if (navigationChanged) {
          _resetVisibleRangeTracking();
        }
        _scheduleVisibleThumbnailRequest();
      },
      builder: (context, state) {
        final cubit = context.read<FileBrowserCubit>();

        return MultiBlocListener(
          listeners: [
            BlocListener<TransferCubit, TransferState>(
              listener: _handleTransferStateChanged,
            ),
          ],
          child: Scaffold(
            body: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(context, state),
                    triggerMode: RefreshIndicatorTriggerMode.onEdge,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: _resolveScrollPhysics(state),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 64, 24, 0),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              Text(
                                '我的空间',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontSize: 28),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '浏览和管理NAS服务器上的文件',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 13,
                                      color: const Color(0xFF6D6C6A),
                                    ),
                              ),
                              const SizedBox(height: 20),
                              FileCategoryFilter(
                                selectedCategory: cubit.currentCategory,
                                onCategoryChanged: state is FileBrowserLoaded
                                    ? (category) =>
                                          cubit.switchCategory(category)
                                    : (_) {},
                              ),
                              const SizedBox(height: 14),
                              if (state is FileBrowserLoaded) ...[
                                PathBreadcrumb(
                                  path: state.currentPath.path,
                                  currentRootId: state.currentRootId,
                                  onTopDirChanged: (rootId) =>
                                      cubit.switchRoot(rootId),
                                  showRootToggle: _isMobileServer(),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ]),
                          ),
                        ),
                        if (state is FileBrowserLoaded) ...[
                          _LoadedFileGridSliver(
                            bottomPadding: state.selectionMode
                                ? widget.bottomPadding +
                                      _selectionActionBarHeight +
                                      28
                                : widget.bottomPadding + 16,
                            getThumbnail: cubit.getThumbnail,
                            watchThumbnail: cubit.watchThumbnail,
                            enableHero:
                                !_isScrollActive && !state.selectionMode,
                            getHeroTag: (file, rootId) =>
                                ImageCacheKeyBuilder.heroTag(
                                  NasPath(rootId: rootId, path: file.path),
                                ),
                            onSelectToggle: cubit.toggleSelection,
                            onLongSelect: (filePath) {
                              cubit.enterSelectionModeAndToggle(filePath);
                              _isDragSelecting = true;
                              _lastDragToggledPath = filePath;
                            },
                            onTap: (loadedState, file) {
                              if (loadedState.selectionMode) {
                                cubit.toggleSelection(file.path);
                              } else if (file.isDirectory) {
                                cubit.navigateToFolder(file.name);
                              } else if (file.isImage || file.isVideo) {
                                _showPreviewDialog(context, file, loadedState);
                              } else if (file.isFile) {
                                _showNonPreviewDownloadDialog(
                                  context,
                                  file,
                                  loadedState.currentRootId,
                                );
                              }
                            },
                            onLongPressNonPreview: (file) =>
                                _showNonPreviewDeleteDialog(context, file),
                          ),
                        ] else if (state is FileBrowserError)
                          SliverToBoxAdapter(
                            child: _ErrorStateCard(
                              message: state.message,
                              onRetry: () => cubit.loadRoot(),
                            ),
                          )
                        else if (state is FileBrowserLoading)
                          const SliverToBoxAdapter(
                            child: _LoadingGridPlaceholder(),
                          )
                        else
                          SliverToBoxAdapter(
                            child: _EmptyRootCard(
                              onRetry: () => cubit.loadRoot(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (state is FileBrowserLoaded && state.selectionMode)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: _selectionActionBarBottomOffset(context),
                    child: _SelectionActionBar(
                      selectedCount: state.selectedPaths.length,
                      onDelete: () => _confirmBatchDelete(context, state),
                      onCancel: cubit.exitSelectionMode,
                    ),
                  ),
                if (state is FileBrowserLoaded)
                  BlocBuilder<TransferCubit, TransferState>(
                    builder: (context, transferState) {
                      if (state.selectionMode) {
                        return const SizedBox.shrink();
                      }
                      final activeUpload = _resolveActiveUploadOverlay(
                        transferState,
                      );
                      final canUpload = state.currentRootWritable;
                      if (!canUpload && activeUpload == null) {
                        return const SizedBox.shrink();
                      }
                      return FileBrowserFloatingActionsWidget(
                        onUploadMediaTap: () =>
                            _pickAndUploadMedia(context, cubit),
                        onUploadFilesTap: () =>
                            _pickAndUploadFiles(context, cubit),
                        bottomPadding: widget.bottomPadding,
                        showUploadAction: canUpload,
                        isUploading: activeUpload != null,
                        uploadFileName: activeUpload?.fileName,
                        uploadProgress: activeUpload?.progress ?? 0,
                      );
                    },
                  ),
                if (state is FileBrowserLoaded && state.selectionMode)
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerUp,
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadedFileGridSliver extends StatelessWidget {
  const _LoadedFileGridSliver({
    required this.bottomPadding,
    required this.getThumbnail,
    required this.watchThumbnail,
    required this.enableHero,
    required this.getHeroTag,
    required this.onSelectToggle,
    required this.onLongSelect,
    required this.onTap,
    required this.onLongPressNonPreview,
  });

  final double bottomPadding;
  final Uint8List? Function(String filePath) getThumbnail;
  final Stream<void> Function(String filePath) watchThumbnail;
  final bool enableHero;
  final String Function(FileEntryEntity file, String rootId) getHeroTag;
  final void Function(String filePath) onSelectToggle;
  final void Function(String filePath) onLongSelect;
  final void Function(FileBrowserLoaded state, FileEntryEntity file) onTap;
  final void Function(FileEntryEntity file) onLongPressNonPreview;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FileBrowserCubit, FileBrowserState>(
      buildWhen: (previous, current) {
        if (previous is FileBrowserLoaded && current is FileBrowserLoaded) {
          return previous.selectionMode != current.selectionMode ||
              previous.isLoadingMore != current.isLoadingMore ||
              !setEquals(previous.selectedPaths, current.selectedPaths) ||
              !identical(previous.filteredFiles, current.filteredFiles);
        }
        return previous.runtimeType != current.runtimeType;
      },
      builder: (context, state) {
        if (state is! FileBrowserLoaded) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        return SliverMainAxisGroup(
          slivers: [
            FileListView(
              files: state.filteredFiles,
              getThumbnail: getThumbnail,
              watchThumbnail: watchThumbnail,
              getHeroTag: (file) => getHeroTag(file, state.currentRootId),
              selectionMode: state.selectionMode,
              selectedPaths: state.selectedPaths,
              onSelectToggle: onSelectToggle,
              onLongSelect: onLongSelect,
              onTap: (file) => onTap(state, file),
              onLongPressNonPreview: onLongPressNonPreview,
              bottomPadding: bottomPadding,
              enableHero: enableHero,
            ),
            if (state.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _SelectionActionBar({
    required this.selectedCount,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已选 $selectedCount 个文件',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2F2E2B),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onDelete,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB64848),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('删除'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onCancel,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF1F0ED),
                foregroundColor: const Color(0xFF4D4A45),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorStateCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorStateCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('目录加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}

class _EmptyRootCard extends StatelessWidget {
  final VoidCallback onRetry;

  const _EmptyRootCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('目录尚未就绪', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '当前还没有拿到可浏览的根目录，确认登录会话后可再次尝试。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('再次加载')),
        ],
      ),
    );
  }
}

class _LoadingGridPlaceholder extends StatelessWidget {
  const _LoadingGridPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        itemCount: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemBuilder: (context, index) =>
            Container(color: const Color(0xFFD9D8D5)),
      ),
    );
  }
}

class _TrackedUploadTask {
  final String rootId;
  final String directoryPath;

  const _TrackedUploadTask({required this.rootId, required this.directoryPath});
}

class _ActiveUploadOverlay {
  final String fileName;
  final double progress;

  const _ActiveUploadOverlay({required this.fileName, required this.progress});
}
