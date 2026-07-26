import 'package:flutter/material.dart' show IconData;

import '../../domain/relay_media_kind.dart';

enum PartnerMessageContentKind { file, mediaPreview, mediaPlaceholder }

class PartnerMessageContent {
  const PartnerMessageContent.file({required this.title})
    : kind = PartnerMessageContentKind.file,
      mediaKind = null,
      thumbnailPath = null,
      placeholderLabel = null;

  const PartnerMessageContent.mediaPreview({
    required this.mediaKind,
    required this.thumbnailPath,
  }) : kind = PartnerMessageContentKind.mediaPreview,
       title = null,
       placeholderLabel = null;

  const PartnerMessageContent.mediaPlaceholder({
    required this.mediaKind,
    this.placeholderLabel,
  }) : kind = PartnerMessageContentKind.mediaPlaceholder,
       title = null,
       thumbnailPath = null;

  final PartnerMessageContentKind kind;
  final String? title;
  final RelayMediaKind? mediaKind;
  final String? thumbnailPath;
  final String? placeholderLabel;
}

class PartnerAvatarSpec {
  const PartnerAvatarSpec({
    this.imagePath,
    this.imageCacheKey,
    this.fallbackIcon,
    this.fallbackInitial,
  });

  final String? imagePath;
  /// Busts Flutter ImageCache / widget identity when the same path is rewritten.
  final String? imageCacheKey;
  final IconData? fallbackIcon;
  final String? fallbackInitial;
}
