import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/widgets/app_network_image.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

/// The "full" (expanded, shrinkOffset == 0) state of the collapsing hero
/// header — see [HeroHeaderDelegate]. Narrowed down from its previous,
/// free-scrolling-sliver-child form: the synopsis and external-link row
/// used to live here too, but neither fits inside a
/// SliverPersistentHeader's bounded [minExtent, maxExtent] box, so they've
/// moved to [AnimeSynopsisSection], an ordinary sliver sibling placed
/// directly below the pinned header.
///
/// Also collapses the previous separate mobile/desktop layouts into one —
/// at header-appropriate heights there isn't room for two visually
/// distinct treatments, matching the same call already made for
/// [HeroHeaderCompact].
class HeroBanner extends StatelessWidget {
  final Anime anime;
  final VoidCallback? onBack;
  final bool uiPerformanceMode;

  const HeroBanner({
    super.key,
    required this.anime,
    this.onBack,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final String? bannerUrl = anime.bannerImage ?? anime.coverImage?.extraLarge;
    final String? posterUrl = anime.coverImage?.extraLarge;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (bannerUrl != null)
          AppNetworkImage(url: bannerUrl, uiPerformanceMode: uiPerformanceMode)
        else
          const ColoredBox(color: AppPalette.surface),

        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppPalette.base.withValues(alpha: 0.2),
                AppPalette.base.withValues(alpha: 0.75),
                AppPalette.base,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),

        Positioned(
          top: 16,
          left: 16,
          child: _FloatingBackButton(
            onBack: onBack,
            uiPerformanceMode: uiPerformanceMode,
          ),
        ),

        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (posterUrl != null)
                _PosterThumb(
                  url: posterUrl,
                  uiPerformanceMode: uiPerformanceMode,
                ),
              const SizedBox(width: 16),
              Expanded(child: _AnimeTextInfo(anime: anime)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PosterThumb extends StatelessWidget {
  final String url;
  final bool uiPerformanceMode;
  const _PosterThumb({required this.url, this.uiPerformanceMode = false});

  @override
  Widget build(BuildContext context) {
    final radii = context.appRadii;

    return Container(
      width: 76,
      height: 114,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radii.small),
        boxShadow: uiPerformanceMode
            ? null
            : [
                BoxShadow(
                  color: AppPalette.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radii.small),
        clipBehavior: uiPerformanceMode ? Clip.hardEdge : Clip.antiAlias,
        child: AppNetworkImage(
          url: url,
          cacheWidth: 200,
          uiPerformanceMode: uiPerformanceMode,
        ),
      ),
    );
  }
}

class _AnimeTextInfo extends StatelessWidget {
  final Anime anime;
  const _AnimeTextInfo({required this.anime});

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          anime.title.display,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: typography.cardTitleProminent.copyWith(
            color: AppPalette.textMain,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _MetaChip(
              label: anime.status?.statusLabel ?? 'UNKNOWN',
              color: anime.status?.statusColor ?? AppPalette.statusDefault,
            ),
            if (anime.episodes != null)
              _MetaChip(
                label: '${anime.episodes} Episodes',
                color: AppPalette.textLight,
              ),
          ],
        ),
      ],
    );
  }
}

class _FloatingBackButton extends StatelessWidget {
  final VoidCallback? onBack;
  final bool uiPerformanceMode;
  const _FloatingBackButton({this.onBack, this.uiPerformanceMode = false});

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

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: typography.metaLabel.copyWith(color: color)),
    );
  }
}
