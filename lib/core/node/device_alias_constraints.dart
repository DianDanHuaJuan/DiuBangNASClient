import 'package:characters/characters.dart';

/// Shared alias length rules for client UI and pre-submit validation.
abstract final class DeviceAliasConstraints {
  static const int maxLength = 32;

  static String normalize(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Returns a user-facing error message, or `null` when valid.
  static String? validate(String? raw, {bool allowEmpty = true}) {
    final normalized = normalize(raw ?? '');
    if (normalized.isEmpty) {
      return allowEmpty ? null : '别名不能为空';
    }
    if (normalized.characters.length > maxLength) {
      return '别名不能超过 $maxLength 个字';
    }
    return null;
  }

  /// Normalizes input for persistence. Empty string means clear alias.
  static String? normalizeForSave(String? raw) {
    final normalized = normalize(raw ?? '');
    if (normalized.isEmpty) {
      return null;
    }
    final error = validate(normalized, allowEmpty: false);
    if (error != null) {
      throw ArgumentError(error);
    }
    return normalized;
  }
}
