import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

/// Small, static building blocks for the collapsed/chrome layer of the
/// hero header — the back button and the status dot. Both are positioned
/// directly by HeroHeaderDelegate and don't change position across the
/// collapse (unlike the title, which HeroHeaderDelegate morphs between a
/// full and compact Rect itself).
class HeroHeaderBackButton extends StatelessWidget {
  final VoidCallback? onBack;
  final bool uiPerformanceMode;

  const HeroHeaderBackButton({
    super.key,
    this.onBack,
    this.uiPerformanceMode = false,
  });

  void _handleTap(BuildContext context) {
    if (onBack != null) {
      onBack!();
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      onTap: () => _handleTap(context),
      builder: (context, hovered) {
        final content = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered
                ? AppPalette.white.withValues(alpha: 0.15)
                : AppPalette.black.withValues(
                    alpha: uiPerformanceMode ? 0.8 : 0.4,
                  ),
            shape: BoxShape.circle,
            border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            size: 18,
            color: AppPalette.textMain,
          ),
        );

        return FrostedContainer(
          uiPerformanceMode: uiPerformanceMode,
          sigma: 12,
          borderRadius: BorderRadius.circular(20),
          child: content,
        );
      },
    );
  }
}

/// Small colored status dot shown next to the title once it's finished
/// migrating into the compact row — a lightweight stand-in for the full
/// state's text status chip, which doesn't fit a single-line compact bar.
class HeroHeaderStatusDot extends StatelessWidget {
  final Anime anime;
  const HeroHeaderStatusDot({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: anime.status?.statusColor ?? AppPalette.statusDefault,
        shape: BoxShape.circle,
      ),
    );
  }
}
