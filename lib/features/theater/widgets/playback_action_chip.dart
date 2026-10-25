import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// Pill-shaped action chip (the Next Episode chip) that fades and slides in
/// while [visible]; while hidden it ignores taps, so [onTap] never fires.
class PlaybackActionChip extends StatelessWidget {
  final bool visible;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const PlaybackActionChip({
    super.key,
    required this.visible,
    required this.label,
    this.icon = Icons.skip_next_rounded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.5),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: IgnorePointer(
          ignoring: !visible,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: AppPalette.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: visible ? onTap : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppPalette.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(icon, color: AppPalette.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
