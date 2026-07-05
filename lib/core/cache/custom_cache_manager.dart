/// CustomCacheManager stub: flutter_cache_manager removed from dependencies.
///
/// This file preserves the public symbol for migration but implements a no-op
/// interface so the codebase builds without flutter_cache_manager. Remove this
/// stub once all callers are migrated to extended_image or other cache layers.

import 'package:flutter/foundation.dart';

class CustomCacheManager {
  static const String key = 'nasImageCache';

  /// Old API: CacheManager instance is no longer available when the plugin is removed.
  /// Keep the getter to avoid breaking imports; it returns `null`.
  static dynamic get instance => null;

  static String? get cachePath => null;

  static bool get isInitialized => false;

  static Future<void> initialize() async {}

  static Future<void> logCacheInfo() async {}
}
