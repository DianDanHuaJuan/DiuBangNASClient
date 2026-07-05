/// 文件输入：BuildContext、本地图库资源选择配置
/// 文件职责：统一封装图库多选逻辑，返回可上传的本地媒体文件信息
/// 文件对外接口：LocalMediaPicker、LocalMediaPickResult、PickedLocalMediaItem
/// 文件包含：LocalMediaPicker、LocalMediaPickResult、PickedLocalMediaItem
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

@visibleForTesting
bool mediaScanShouldContinue({bool Function()? shouldCancel}) {
  return shouldCancel?.call() != true;
}

class LocalMediaPicker {
  const LocalMediaPicker();

  static const _accentColor = Color(0xFF3D8A5A);
  static const _pickerPermissionOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      mediaLocation: false,
    ),
  );

  Future<LocalMediaPickResult> pickMedia(
    BuildContext context, {
    int maxAssets = 500,
  }) async {
    return pickMediaFiltered(
      context,
      maxAssets: maxAssets,
      includeImages: true,
      includeVideos: true,
    );
  }

  Future<LocalMediaPickResult> pickMediaFiltered(
    BuildContext context, {
    int maxAssets = 500,
    required bool includeImages,
    required bool includeVideos,
  }) async {
    if (!includeImages && !includeVideos) {
      return const LocalMediaPickResult(items: <PickedLocalMediaItem>[]);
    }

    final assets = await _pickMediaWithCustomDelegate(
      context,
      maxAssets: maxAssets,
      includeImages: includeImages,
      includeVideos: includeVideos,
    );

    if (assets == null || assets.isEmpty) {
      return const LocalMediaPickResult(items: <PickedLocalMediaItem>[]);
    }

    final items = <PickedLocalMediaItem>[];
    var unavailableCount = 0;

    for (final asset in assets) {
      final file = await asset.file;
      if (file == null || !await file.exists()) {
        unavailableCount += 1;
        continue;
      }

      final fileName = _resolveAssetFileName(asset, file);
      items.add(
        PickedLocalMediaItem(
          id: asset.id,
          localPath: file.path,
          displayName: fileName,
          size: await file.length(),
          mimeType: guessMimeTypeFromFileName(fileName),
          createdAt: asset.createDateTime,
          modifiedAt: asset.modifiedDateTime,
          durationSeconds: asset.duration,
        ),
      );
    }

    return LocalMediaPickResult(
      items: List.unmodifiable(items),
      unavailableCount: unavailableCount,
    );
  }

  Future<List<AssetEntity>?> _pickMediaWithCustomDelegate(
    BuildContext context, {
    required int maxAssets,
    required bool includeImages,
    required bool includeVideos,
  }) async {
    final sharedSelection = ValueNotifier<List<AssetEntity>>(
      const <AssetEntity>[],
    );
    final pickerTheme = _buildPickerTheme(context);
    final locale = Localizations.maybeLocaleOf(context);
    final filterOptions = _buildFilterOptions();
    final permissionState = await AssetPicker.permissionCheck(
      requestOption: _pickerPermissionOption,
    );
    if (!context.mounted) {
      return null;
    }

    final useFilterTabs = includeImages && includeVideos;
    if (useFilterTabs) {
      final allProvider = _SynchronizedAssetPickerProvider(
        sharedSelection: sharedSelection,
        maxAssets: maxAssets,
        requestType: RequestType.common,
        filterOptions: filterOptions,
      );
      final videoProvider = _SynchronizedAssetPickerProvider(
        sharedSelection: sharedSelection,
        maxAssets: maxAssets,
        requestType: RequestType.video,
        filterOptions: filterOptions,
      );
      final imageProvider = _SynchronizedAssetPickerProvider(
        sharedSelection: sharedSelection,
        maxAssets: maxAssets,
        requestType: RequestType.image,
        filterOptions: filterOptions,
      );
      final delegate = _BackupGalleryPickerBuilder(
        provider: allProvider,
        videosProvider: videoProvider,
        imagesProvider: imageProvider,
        sharedSelection: sharedSelection,
        initialPermission: permissionState,
        pickerTheme: pickerTheme,
        locale: locale,
      );
      return AssetPicker.pickAssetsWithDelegate<
        AssetEntity,
        AssetPathEntity,
        _SynchronizedAssetPickerProvider,
        _BackupGalleryPickerBuilder
      >(
        context,
        delegate: delegate,
        permissionRequestOption: _pickerPermissionOption,
      );
    }

    final requestType = _resolveRequestType(
      includeImages: includeImages,
      includeVideos: includeVideos,
    );
    final provider = _SynchronizedAssetPickerProvider(
      sharedSelection: sharedSelection,
      maxAssets: maxAssets,
      requestType: requestType,
      filterOptions: filterOptions,
    );
    final delegate = _SimpleGalleryPickerBuilder(
      provider: provider,
      sharedSelection: sharedSelection,
      initialPermission: permissionState,
      pickerTheme: pickerTheme,
      locale: locale,
    );
    return AssetPicker.pickAssetsWithDelegate<
      AssetEntity,
      AssetPathEntity,
      _SynchronizedAssetPickerProvider,
      _SimpleGalleryPickerBuilder
    >(
      context,
      delegate: delegate,
      permissionRequestOption: _pickerPermissionOption,
    );
  }

  FilterOptionGroup _buildFilterOptions() {
    return FilterOptionGroup(containsPathModified: false);
  }

  ThemeData _buildPickerTheme(BuildContext context) {
    final baseTheme = Theme.of(context);
    final colorScheme = baseTheme.colorScheme.copyWith(
      primary: _accentColor,
      secondary: _accentColor,
      surface: Colors.white,
    );
    return baseTheme.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      cardColor: Colors.white,
      dividerColor: const Color(0xFFE5E7EB),
      focusColor: const Color(0xFFF3F4F6),
      splashColor: const Color(0xFFE5E7EB),
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
        actionsIconTheme: const IconThemeData(color: Color(0xFF111827)),
        titleTextStyle: baseTheme.textTheme.titleMedium?.copyWith(
          color: const Color(0xFF111827),
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomAppBarTheme: const BottomAppBarThemeData(color: Colors.white),
      iconTheme: const IconThemeData(color: Color(0xFF111827)),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: const Color(0xFF111827),
        displayColor: const Color(0xFF111827),
      ),
    );
  }

  RequestType _resolveRequestType({
    required bool includeImages,
    required bool includeVideos,
  }) {
    if (includeImages && includeVideos) {
      return RequestType.common;
    }
    if (includeImages) {
      return RequestType.image;
    }
    return RequestType.video;
  }

  Future<LocalMediaPickResult> loadAllMedia({
    int pageSize = 300,
    void Function(LocalMediaScanProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) {
    return loadAllMediaFiltered(
      pageSize: pageSize,
      includeImages: true,
      includeVideos: true,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
  }

  Future<LocalMediaPickResult> loadAllMediaFiltered({
    int pageSize = 300,
    required bool includeImages,
    required bool includeVideos,
    void Function(LocalMediaScanProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    if (!includeImages && !includeVideos) {
      return const LocalMediaPickResult(items: <PickedLocalMediaItem>[]);
    }

    final permissionState = await PhotoManager.requestPermissionExtend();
    if (!permissionState.hasAccess) {
      return const LocalMediaPickResult(items: <PickedLocalMediaItem>[]);
    }

    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common,
    );
    if (paths.isEmpty) {
      return const LocalMediaPickResult(items: <PickedLocalMediaItem>[]);
    }

    final rootPath = paths.first;
    final totalCount = await rootPath.assetCountAsync;
    final items = <PickedLocalMediaItem>[];
    var unavailableCount = 0;
    var scannedAssets = 0;
    final pageCount = (totalCount / pageSize).ceil();

    for (var page = 0; page < pageCount; page += 1) {
      if (!mediaScanShouldContinue(shouldCancel: shouldCancel)) {
        break;
      }
      final assets = await rootPath.getAssetListPaged(
        page: page,
        size: pageSize,
      );
      if (assets.isEmpty) {
        break;
      }
      scannedAssets += assets.length;

      for (final asset in assets) {
        if (!mediaScanShouldContinue(shouldCancel: shouldCancel)) {
          break;
        }
        if (!_matchesAssetType(
          asset,
          includeImages: includeImages,
          includeVideos: includeVideos,
        )) {
          continue;
        }

        final file = await asset.file;
        if (file == null || !await file.exists()) {
          unavailableCount += 1;
          continue;
        }

        final fileName = _resolveAssetFileName(asset, file);
        items.add(
          PickedLocalMediaItem(
            id: asset.id,
            localPath: file.path,
            displayName: fileName,
            size: await file.length(),
            mimeType: guessMimeTypeFromFileName(fileName),
            createdAt: asset.createDateTime,
            modifiedAt: asset.modifiedDateTime,
            durationSeconds: asset.duration,
          ),
        );
      }

      if (!mediaScanShouldContinue(shouldCancel: shouldCancel)) {
        break;
      }

      onProgress?.call(
        LocalMediaScanProgress(
          scannedAssets: scannedAssets.clamp(0, totalCount),
          totalAssets: totalCount,
          discoveredItems: items.length,
          unavailableCount: unavailableCount,
        ),
      );
    }

    return LocalMediaPickResult(
      items: List.unmodifiable(items),
      unavailableCount: unavailableCount,
    );
  }

  bool _matchesAssetType(
    AssetEntity asset, {
    required bool includeImages,
    required bool includeVideos,
  }) {
    if (asset.type == AssetType.image) {
      return includeImages;
    }
    if (asset.type == AssetType.video) {
      return includeVideos;
    }
    return includeImages || includeVideos;
  }

  String _resolveAssetFileName(AssetEntity asset, File file) {
    final title = asset.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return p.basename(file.path);
  }
}

enum _BackupGalleryFilter {
  all('全部'),
  image('图片'),
  video('视频');

  const _BackupGalleryFilter(this.label);

  final String label;
}

class _SynchronizedAssetPickerProvider extends DefaultAssetPickerProvider {
  _SynchronizedAssetPickerProvider({
    required this.sharedSelection,
    required super.maxAssets,
    required super.requestType,
    required super.filterOptions,
  }) : super(
         selectedAssets: sharedSelection.value,
         initializeDelayDuration: Duration.zero,
       ) {
    sharedSelection.addListener(_applySharedSelection);
  }

  final ValueNotifier<List<AssetEntity>> sharedSelection;
  bool _syncingSelection = false;

  void _applySharedSelection() {
    if (_sameSelection(sharedSelection.value, super.selectedAssets)) {
      return;
    }
    _syncingSelection = true;
    super.selectedAssets = List<AssetEntity>.from(sharedSelection.value);
    _syncingSelection = false;
  }

  bool _sameSelection(List<AssetEntity> left, List<AssetEntity> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  set selectedAssets(List<AssetEntity> value) {
    final normalized = List<AssetEntity>.from(value);
    if (_sameSelection(normalized, super.selectedAssets)) {
      return;
    }
    super.selectedAssets = normalized;
    if (_syncingSelection) {
      return;
    }
    if (_sameSelection(sharedSelection.value, normalized)) {
      return;
    }
    sharedSelection.value = List<AssetEntity>.unmodifiable(normalized);
  }

  @override
  void dispose() {
    sharedSelection.removeListener(_applySharedSelection);
    super.dispose();
  }
}

/// Shared tap zones: top-end hot area selects, the rest previews.
mixin _NasGalleryPickerInteraction<T extends DefaultAssetPickerProvider>
    on DefaultAssetPickerBuilderDelegate<T> {
  static const indicatorVisualSize = 18.0;
  static const indicatorHitSize = 35.0;
  static const indicatorInset = 6.0;

  @override
  Widget selectedBackdrop(
    BuildContext context,
    int index,
    AssetEntity asset,
  ) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: isPreviewEnabled
            ? () {
                viewAsset(context, index, asset);
              }
            : null,
        child: Consumer<T>(
          builder: (context, picker, _) {
            final selected = picker.selectedAssets.contains(asset);
            return AnimatedContainer(
              duration: switchingPathDuration,
              color: selected
                  ? LocalMediaPicker._accentColor.withValues(alpha: 0.28)
                  : Colors.transparent,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget selectIndicator(
    BuildContext context,
    int index,
    AssetEntity asset,
  ) {
    final duration = switchingPathDuration * 0.75;

    return Selector<T, String>(
      selector: (_, picker) => picker.selectedDescriptions,
      builder: (context, descriptions, _) {
        final selected = descriptions.contains(asset.toString());
        final order = context.read<T>().selectedAssets.indexOf(asset) + 1;

        return PositionedDirectional(
          top: indicatorInset,
          end: indicatorInset,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => selectAsset(context, asset, index, selected),
            child: SizedBox(
              width: indicatorHitSize,
              height: indicatorHitSize,
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: AnimatedContainer(
                  duration: duration,
                  width: indicatorVisualSize,
                  height: indicatorVisualSize,
                  decoration: BoxDecoration(
                    color: selected
                        ? LocalMediaPicker._accentColor
                        : Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 1.5,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: duration,
                    reverseDuration: duration,
                    child: selected
                        ? (isSingleAssetMode
                              ? const Icon(
                                  Icons.check,
                                  key: ValueKey<String>('selected'),
                                  color: Colors.white,
                                  size: 12,
                                )
                              : FittedBox(
                                  key: ValueKey<int>(order),
                                  child: Text(
                                    '$order',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                ))
                        : const SizedBox.shrink(
                            key: ValueKey<String>('unselected'),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _SimpleGalleryPickerBuilder
    extends DefaultAssetPickerBuilderDelegate<_SynchronizedAssetPickerProvider>
    with _NasGalleryPickerInteraction<_SynchronizedAssetPickerProvider> {
  _SimpleGalleryPickerBuilder({
    required super.provider,
    required this.sharedSelection,
    required super.initialPermission,
    super.pickerTheme,
    super.locale,
  }) : super(shouldRevertGrid: false, dragToSelect: true);

  final ValueNotifier<List<AssetEntity>> sharedSelection;

  @override
  void dispose() {
    super.dispose();
    sharedSelection.dispose();
  }
}

final class _BackupGalleryPickerBuilder
    extends
        DefaultAssetPickerBuilderDelegate<_SynchronizedAssetPickerProvider>
    with _NasGalleryPickerInteraction<_SynchronizedAssetPickerProvider> {
  _BackupGalleryPickerBuilder({
    required super.provider,
    required this.videosProvider,
    required this.imagesProvider,
    required this.sharedSelection,
    required super.initialPermission,
    super.pickerTheme,
    super.locale,
  }) : super(shouldRevertGrid: false, dragToSelect: true);

  final _SynchronizedAssetPickerProvider videosProvider;
  final _SynchronizedAssetPickerProvider imagesProvider;
  final ValueNotifier<List<AssetEntity>> sharedSelection;

  late final TabController _tabController;

  _BackupGalleryFilter get _currentFilter =>
      _BackupGalleryFilter.values[_tabController.index];

  _SynchronizedAssetPickerProvider get _activeProvider =>
      _providerForFilter(_currentFilter);

  _SynchronizedAssetPickerProvider _providerForFilter(
    _BackupGalleryFilter filter,
  ) {
    return switch (filter) {
      _BackupGalleryFilter.all => provider,
      _BackupGalleryFilter.video => videosProvider,
      _BackupGalleryFilter.image => imagesProvider,
    };
  }

  @override
  void initState(
    AssetPickerState<AssetEntity, AssetPathEntity, _BackupGalleryPickerBuilder>
    state,
  ) {
    super.initState(state);
    _tabController = TabController(
      length: _BackupGalleryFilter.values.length,
      vsync: state,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    videosProvider.dispose();
    imagesProvider.dispose();
    super.dispose();
    sharedSelection.dispose();
  }

  Future<void> _switchFilter(_BackupGalleryFilter filter) async {
    if (_currentFilter == filter) {
      return;
    }
    isSwitchingPath.value = false;
    _tabController.animateTo(filter.index);
    await _synchronizeCurrentPath(
      previousProvider: _activeProvider,
      nextProvider: _providerForFilter(filter),
    );
  }

  Future<void> _synchronizeCurrentPath({
    required _SynchronizedAssetPickerProvider previousProvider,
    required _SynchronizedAssetPickerProvider nextProvider,
  }) async {
    if (identical(previousProvider, nextProvider)) {
      return;
    }
    if (nextProvider.paths.isEmpty) {
      await nextProvider.getPaths();
    }
    final previousPath = previousProvider.currentPath?.path;
    if (previousPath == null) {
      if (nextProvider.currentPath != null &&
          nextProvider.currentAssets.isEmpty) {
        await nextProvider.getAssetsFromCurrentPath();
      }
      return;
    }
    for (final wrapper in nextProvider.paths) {
      if (wrapper.path.id == previousPath.id) {
        await nextProvider.switchPath(wrapper);
        return;
      }
    }
    if (nextProvider.currentPath != null &&
        nextProvider.currentAssets.isEmpty) {
      await nextProvider.getAssetsFromCurrentPath();
    }
  }

  @override
  AssetPickerAppBar appBar(BuildContext context) {
    final appBar = AssetPickerAppBar(
      backgroundColor: theme.appBarTheme.backgroundColor,
      centerTitle: true,
      leading: backButton(context),
      blurRadius: isAppleOS(context) ? appleOSBlurRadius : 0,
      actionsPadding: const EdgeInsetsDirectional.only(end: 8),
      title: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) => Semantics(
          onTapHint: textDelegate.sActionSwitchPathLabel,
          child: pathEntitySelector(context),
        ),
      ),
      actions: const <Widget>[],
      bottom: _buildFilterBar(context),
    );
    appBarPreferredSize ??= appBar.preferredSize;
    return appBar;
  }

  PreferredSizeWidget _buildFilterBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(40),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _BackupGalleryFilter.values.indexed
                  .map((entry) {
                    final filter = entry.$2;
                    final active = _currentFilter == filter;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_switchFilter(filter)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          filter.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? LocalMediaPicker._accentColor
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget pathEntitySelector(BuildContext context) {
    final activeProvider = _activeProvider;
    return ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
      value: activeProvider,
      builder: (context, _) {
        return UnconstrainedBox(
          child: GestureDetector(
            onTap: () {
              if (isPermissionLimited && activeProvider.isAssetsEmpty) {
                PhotoManager.presentLimited();
                return;
              }
              if (activeProvider.currentPath == null) {
                return;
              }
              isSwitchingPath.value = !isSwitchingPath.value;
            },
            child: Container(
              height: 28,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.42,
              ),
              padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: const Color(0xFFF3F4F6),
              ),
              child:
                  Selector<
                    _SynchronizedAssetPickerProvider,
                    PathWrapper<AssetPathEntity>?
                  >(
                    selector: (_, provider) => provider.currentPath,
                    builder: (context, wrapper, child) {
                      final path = wrapper?.path;
                      final displayName = switch (path) {
                        null when isPermissionLimited =>
                          textDelegate.changeAccessibleLimitedAssets,
                        null => '选择目录',
                        _ when isPermissionLimited && path.isAll =>
                          textDelegate.accessiblePathName,
                        _ => pathNameBuilder?.call(path) ?? path.name,
                      };
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          ValueListenableBuilder<bool>(
                            valueListenable: isSwitchingPath,
                            builder: (context, isSwitching, child) {
                              return Transform.rotate(
                                angle: isSwitching ? 3.1415926535897932 : 0,
                                child: child,
                              );
                            },
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget confirmButton(BuildContext context) {
    return ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
      value: _activeProvider,
      builder: (context, _) => super.confirmButton(context),
    );
  }

  @override
  Widget androidLayout(BuildContext context) {
    return AssetPickerAppBarWrapper(
      appBar: appBar(context),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
            value: provider,
            builder: (context, _) => _buildGrid(context),
          ),
          ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
            value: imagesProvider,
            builder: (context, _) => _buildGrid(context),
          ),
          ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
            value: videosProvider,
            builder: (context, _) => _buildGrid(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget appleOSLayout(BuildContext context) {
    Widget layout(BuildContext context) {
      return Stack(
        children: <Widget>[
          TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
                value: provider,
                builder: (context, _) => _buildGrid(context),
              ),
              ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
                value: imagesProvider,
                builder: (context, _) => _buildGrid(context),
              ),
              ChangeNotifierProvider<_SynchronizedAssetPickerProvider>.value(
                value: videosProvider,
                builder: (context, _) => _buildGrid(context),
              ),
            ],
          ),
          appBar(context),
        ],
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: permissionOverlayDisplay,
      builder: (context, value, child) {
        if (value) {
          return ExcludeSemantics(child: child);
        }
        return child!;
      },
      child: layout(context),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return Consumer<_SynchronizedAssetPickerProvider>(
      builder: (context, provider, child) {
        final hasAssetsToDisplay = provider.hasAssetsToDisplay;
        final shouldBuildSpecialItems = assetsGridSpecialItemsFinalized(
          context: context,
          path: provider.currentPath?.path,
        ).isNotEmpty;
        final shouldDisplayAssets =
            hasAssetsToDisplay || shouldBuildSpecialItems;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: shouldDisplayAssets
              ? Stack(
                  children: <Widget>[
                    RepaintBoundary(
                      child: Column(
                        children: <Widget>[
                          Expanded(child: assetsGridBuilder(context)),
                          bottomActionBar(context),
                        ],
                      ),
                    ),
                    pathEntityListBackdrop(context),
                    pathEntityListWidget(context),
                  ],
                )
              : loadingIndicator(context),
        );
      },
    );
  }
}

@visibleForTesting
Rect nasGalleryPickerSelectionHitRect(Size cellSize) {
  return Rect.fromLTWH(
    cellSize.width -
        _NasGalleryPickerInteraction.indicatorHitSize -
        _NasGalleryPickerInteraction.indicatorInset,
    _NasGalleryPickerInteraction.indicatorInset,
    _NasGalleryPickerInteraction.indicatorHitSize,
    _NasGalleryPickerInteraction.indicatorHitSize,
  );
}

class LocalMediaScanProgress {
  const LocalMediaScanProgress({
    required this.scannedAssets,
    required this.totalAssets,
    required this.discoveredItems,
    required this.unavailableCount,
  });

  final int scannedAssets;
  final int totalAssets;
  final int discoveredItems;
  final int unavailableCount;
}

String? guessMimeTypeFromFileName(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  return switch (ext) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    '.bmp' => 'image/bmp',
    '.heic' || '.heif' => 'image/heic',
    '.mp4' => 'video/mp4',
    '.mov' => 'video/quicktime',
    '.mkv' => 'video/x-matroska',
    '.avi' => 'video/x-msvideo',
    '.webm' => 'video/webm',
    '.3gp' => 'video/3gpp',
    _ => null,
  };
}

class LocalMediaPickResult {
  final List<PickedLocalMediaItem> items;
  final int unavailableCount;

  const LocalMediaPickResult({required this.items, this.unavailableCount = 0});
}

class PickedLocalMediaItem {
  final String id;
  final String localPath;
  final String displayName;
  final int size;
  final String? mimeType;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final int? durationSeconds;

  const PickedLocalMediaItem({
    required this.id,
    required this.localPath,
    required this.displayName,
    required this.size,
    this.mimeType,
    this.createdAt,
    this.modifiedAt,
    this.durationSeconds,
  });
}
