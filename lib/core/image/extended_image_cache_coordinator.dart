/// 文件输入：图片 URL、缓存 Key、请求头、BuildContext
/// 文件职责：统一封装 extended_image 的缓存读取、预取和清理能力
/// 文件对外接口：ExtendedImageCacheCoordinator
/// 文件包含：ExtendedImageCacheCoordinator
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../network/trusted_media_cache_service.dart';

/// 输入：图片 URL、缓存 Key、请求头、BuildContext。
/// 职责：封装预取、磁盘缓存读取和缓存清理，避免页面直接依赖底层缓存函数。
/// 对外接口：prefetch()、getCachedFile()、clearCachedFile()。
class ExtendedImageCacheCoordinator {
  static const Duration defaultCacheMaxAge = Duration(days: 7);

  ExtendedImageCacheCoordinator({
    required TrustedMediaCacheService mediaCacheService,
  }) : _mediaCacheService = mediaCacheService;

  final TrustedMediaCacheService _mediaCacheService;

  Future<void> prefetch({
    required BuildContext context,
    required String url,
    required String cacheKey,
    Map<String, String>? headers,
    Duration cacheMaxAge = defaultCacheMaxAge,
  }) async {
    await _mediaCacheService.cacheFile(
      url: url,
      cacheKey: cacheKey,
      headers: headers,
    );
  }

  Future<File?> getCachedFile({required String url, required String cacheKey}) {
    return _mediaCacheService.getCachedFile(url: url, cacheKey: cacheKey);
  }

  Future<File> cacheFile({
    required String url,
    required String cacheKey,
    Map<String, String>? headers,
    bool forceRefresh = false,
  }) {
    return _mediaCacheService.cacheFile(
      url: url,
      cacheKey: cacheKey,
      headers: headers,
      forceRefresh: forceRefresh,
    );
  }

  Future<bool> clearCachedFile({
    required String url,
    required String cacheKey,
  }) {
    return _mediaCacheService.clearCachedFile(url: url, cacheKey: cacheKey);
  }
}
