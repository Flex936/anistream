import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

/// The "compact" (fully shrunk) state of the collapsing hero header — see
/// [HeroHeaderDelegate]. One layout for both mobile and desktop breakpoints;
/// at this height there's no room for a distinct treatment per device.
class HeroHeaderCompact extends StatelessWidget {
  final Anime anime;
  final VoidCallback? onBack;
  final bool uiPerformanceMode;

  const HeroHeaderCompact({
    super.key,
    required this.anime,
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
    return FrostedContainer(
      uiPerformanceMode: uiPerformanceMode,
      child: Container(
        color: AppPalette.base.withValues(
          alpha: uiPerformanceMode ? 0.98 : 0.85,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              HoverFocusBuilder(
                onTap: () => _handleTap(context),
                builder: (context, hovered) => Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hovered
                        ? AppPalette.white.withValues(alpha: 0.1)
                        : AppPalette.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: AppPalette.textMain,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: anime.status?.statusColor ?? AppPalette.statusDefault,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  anime.title.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.textMain,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
