import 'package:flutter/material.dart';

class SelectionBadge extends StatelessWidget {
  final bool selected;
  final Widget child;

  const SelectionBadge({
    required this.selected,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (selected)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF3D8A5A),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
      ],
    );
  }
}
