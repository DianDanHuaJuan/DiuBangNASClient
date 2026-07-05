import 'dart:io';

import 'package:flutter/material.dart';

import '../../features/relay/presentation/widgets/partner_message_content.dart';
import 'platform_icon.dart';

class UserAvatar extends StatelessWidget {
  final PartnerAvatarSpec spec;
  final double size;

  const UserAvatar({super.key, required this.spec, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final imagePath = spec.imagePath?.trim();
    if (imagePath != null && imagePath.isNotEmpty && File(imagePath).existsSync()) {
      final file = File(imagePath);
      return CircleAvatar(
        key: ValueKey(
          '$imagePath-${file.lastModifiedSync().millisecondsSinceEpoch}',
        ),
        radius: size / 2,
        backgroundImage: FileImage(file),
      );
    }

    final initial = spec.fallbackInitial?.trim();
    if (initial != null && initial.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: const Color(0xFFE8E5E0),
        child: Text(
          initial.characters.first.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFF2F2E2B),
            fontWeight: FontWeight.w700,
            fontSize: size * 0.38,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFE8E5E0),
      child: Icon(
        spec.fallbackIcon ?? Icons.person_rounded,
        size: size * 0.52,
        color: const Color(0xFF6D6C6A),
      ),
    );
  }
}

PartnerAvatarSpec selfAvatarSpec({
  required String? customAvatarPath,
  required String displayName,
}) {
  final initial = displayName.trim().isEmpty ? null : displayName.trim();
  return PartnerAvatarSpec(
    imagePath: customAvatarPath,
    fallbackIcon: Icons.smartphone_rounded,
    fallbackInitial: initial,
  );
}

PartnerAvatarSpec peerAvatarSpec({
  required String? platform,
  required String displayName,
  String? customAvatarPath,
}) {
  return PartnerAvatarSpec(
    imagePath: customAvatarPath,
    fallbackIcon: platformIconFor(platform) ?? Icons.devices_rounded,
    fallbackInitial: displayName.trim().isEmpty ? null : displayName.trim(),
  );
}
