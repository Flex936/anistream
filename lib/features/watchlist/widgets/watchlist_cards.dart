import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/media_list.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/utils/html_utils.dart';
import '../../../shared/utils/perf_animations.dart';
import '../../../shared/widgets/app_network_image.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

class HeroCard extends StatelessWidget {
  final MediaListEntry entry;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;
  final bool autofocus;
  final bool uiPerformanceMode;

  const HeroCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onHover,
    this.autofocus = false,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    final progress = entry.progress;

    final typography = context.appTypography;
    final radii = context.appRadii;

    final imgUrl =
        media.bannerImage ??
        media.coverImage?.large ??
        media.coverImage?.extraLarge;

    double percent = 0.0;
    if (media.episodes != null && media.episodes! > 0) {
      percent = progress / media.episodes!;
    } else if (progress > 0) {
      percent = 0.1;
    }

    return HoverFocusBuilder(
      autofocus: autofocus,
      onTap: onTap,
      onHoverChanged: onHover,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radii.small),
          border: Border.all(
            color: hovered
                ? AppPalette.primary.withValues(alpha: 0.5)
                : AppPalette.border,
          ),
          boxShadow: (hovered && !uiPerformanceMode)
              ? [
                  BoxShadow(
                    color: AppPalette.primary.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radii.small),
          // Clip.hardEdge under Performant mode — see FrostedContainer's
          // doc comment for the rationale.
          clipBehavior: uiPerformanceMode ? Clip.hardEdge : Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppNetworkImage(
                url: imgUrl,
                scale: (hovered && !uiPerformanceMode) ? 1.05 : 1.0,
                cacheWidth: 600,
                uiPerformanceMode: uiPerformanceMode,
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppPalette.transparent,
                      AppPalette.black.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
              Center(
                child: AnimatedScale(
                  scale: (hovered && !uiPerformanceMode) ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.primary.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: AppPalette.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.title.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.cardTitleProminent.copyWith(
                        color: AppPalette.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Next: Episode ${progress + 1}',
                      style: typography.tileSubtitle.copyWith(
                        color: AppPalette.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  alignment: Alignment.centerLeft,
                  color: AppPalette.black,
                  child: FractionallySizedBox(
                    widthFactor: percent.clamp(0.0, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppPalette.primary,
                        boxShadow: [
                          BoxShadow(color: AppPalette.primary, blurRadius: 4),
                        ],
                      ),
                    ),
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

class ListCard extends StatelessWidget {
  final MediaListEntry entry;
  final bool showProgress;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;
  final bool autofocus;
  final bool uiPerformanceMode;

  const ListCard({
    super.key,
    required this.entry,
    required this.showProgress,
    required this.onTap,
    required this.onHover,
    this.autofocus = false,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    final isMobile = context.isMobile;

    final typography = context.appTypography;
    final radii = context.appRadii;
    final cardSizes = context.appCardSizes;

    return HoverFocusBuilder(
      autofocus: autofocus,
      onTap: onTap,
      onHoverChanged: onHover,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hovered
              ? AppPalette.surface.withValues(alpha: 0.8)
              : AppPalette.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(radii.small),
          border: Border.all(
            color: hovered
                ? AppPalette.primary.withValues(alpha: 0.5)
                : AppPalette.border,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              // Matches search_input.dart's own 32x48 result-row cover
              // art radius.
              borderRadius: BorderRadius.circular(radii.tag),
              // Clip.hardEdge under Performant mode — see
              // FrostedContainer's doc comment for the rationale.
              clipBehavior: uiPerformanceMode ? Clip.hardEdge : Clip.antiAlias,
              child: AspectRatio(
                // Matches AniList's coverImage art (2:3) — the same
                // canonical ratio AnimeCard/WatchlistCard/CalendarCard
                // share via AppCardSizes.
                aspectRatio: cardSizes.posterAspectRatio,
                child: AppNetworkImage(
                  url: media.coverImage?.large ?? media.coverImage?.extraLarge,
                  scale: (hovered && !uiPerformanceMode) ? 1.05 : 1.0,
                  cacheWidth: 300,
                  uiPerformanceMode: uiPerformanceMode,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.cardTitleProminent.copyWith(
                      color: AppPalette.textMain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        // metaLabel sets no `height`, so mixing it into
                        // this Text.rich alongside the plain-literal
                        // spans below can't introduce a per-span
                        // line-height mismatch.
                        TextSpan(
                          text: (media.status ?? 'UNKNOWN').replaceAll(
                            '_',
                            ' ',
                          ),
                          style: typography.metaLabel.copyWith(
                            color:
                                media.status?.statusColor ??
                                AppPalette.statusDefault,
                          ),
                        ),
                        // Left as plain literals (separator + score + EPS
                        // suffix): 12/w400, distinct from metaLabel's w600.
                        const TextSpan(
                          text: '  •  ',
                          style: TextStyle(
                            color: AppPalette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: '★ ${(media.averageScore ?? 0) / 10}',
                          style: typography.metaLabel.copyWith(
                            color: AppPalette.accent,
                          ),
                        ),
                        TextSpan(
                          text: '  •  ${media.episodes ?? "?"} EPS',
                          style: const TextStyle(
                            color: AppPalette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!isMobile &&
                      media.genres != null &&
                      media.genres!.isNotEmpty) ...[
                    SizedBox(
                      height: 16,
                      child: ClipRect(
                        child: Wrap(
                          spacing: 8,
                          // Left as a plain literal (11pt) — doesn't
                          // belong to any typography token; both nearby
                          // candidates (metaLabel/badgeLabel) are a
                          // different size.
                          children: media.genres!
                              .take(3)
                              .map(
                                (g) => Text(
                                  '#$g',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppPalette.primary,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: Text(
                      stripAnilistHtml(media.description),
                      maxLines: isMobile ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: typography.cardSummary.copyWith(
                        color: AppPalette.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WatchlistCard extends StatelessWidget {
  final MediaListEntry entry;
  final String listStatus;
  final bool showProgress;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;
  final bool autofocus;
  final bool uiPerformanceMode;

  /// Fixed height of the text block below the poster — the title line
  /// plus its surrounding spacing, plus the episode/airing line.
  /// `WatchlistScreen`'s grid needs this on top of the width-driven
  /// poster height to size its cells without clipping the text.
  static const double kTextBlockHeight = 48;

  const WatchlistCard({
    super.key,
    required this.entry,
    required this.listStatus,
    required this.showProgress,
    required this.onTap,
    required this.onHover,
    this.autofocus = false,
    this.uiPerformanceMode = false,
  });

  String get _overlayLabel {
    if (listStatus == 'COMPLETED') return 'Watch Again';
    if (listStatus == 'PLANNING') return 'Start Watching';
    return 'View Details';
  }

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    final progress = entry.progress;
    final nextEp = media.nextAiringEpisode;

    final typography = context.appTypography;
    final radii = context.appRadii;
    final materials = context.appMaterials;
    final cardSizes = context.appCardSizes;

    double percent = 0.0;
    if (media.episodes != null && media.episodes! > 0) {
      percent = progress / media.episodes!;
    } else if (progress > 0) {
      percent = 0.1;
    }

    return HoverFocusBuilder(
      autofocus: autofocus,
      onTap: onTap,
      onHoverChanged: onHover,
      builder: (context, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            // Matches AniList's coverImage art (2:3) — the same
            // canonical ratio AnimeCard/CalendarCard/ListCard share via
            // AppCardSizes.
            aspectRatio: cardSizes.posterAspectRatio,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radii.small),
                border: Border.all(
                  color: hovered
                      ? AppPalette.primary.withValues(alpha: 0.55)
                      : AppPalette.border,
                ),
                boxShadow: (hovered && !uiPerformanceMode)
                    ? [
                        BoxShadow(
                          color: AppPalette.primary.withValues(alpha: 0.18),
                          blurRadius: 24,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radii.small),
                // Clip.hardEdge under Performant mode — see
                // FrostedContainer's doc comment for the rationale.
                clipBehavior: uiPerformanceMode
                    ? Clip.hardEdge
                    : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNetworkImage(
                      url:
                          media.coverImage?.large ??
                          media.coverImage?.extraLarge,
                      scale: (hovered && !uiPerformanceMode) ? 1.05 : 1.0,
                      cacheWidth: 450,
                      uiPerformanceMode: uiPerformanceMode,
                    ),

                    if (showProgress)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: FrostedContainer(
                          uiPerformanceMode: uiPerformanceMode,
                          sigma: materials.subtle,
                          borderRadius: BorderRadius.circular(radii.tag),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppPalette.black.withValues(
                                alpha: uiPerformanceMode ? 0.85 : 0.6,
                              ),
                              border: Border.all(
                                color: AppPalette.white.withValues(alpha: 0.15),
                              ),
                              borderRadius: BorderRadius.circular(radii.tag),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.play_arrow_rounded,
                                  color: AppPalette.primary,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'EP $progress / ${media.episodes ?? "?"}',
                                  style: typography.badgeLabel.copyWith(
                                    color: AppPalette.textMain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    _PlayOverlay(
                      visible: hovered,
                      label: _overlayLabel,
                      uiPerformanceMode: uiPerformanceMode,
                    ),

                    if (showProgress)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          alignment: Alignment.centerLeft,
                          color: AppPalette.black,
                          child: FractionallySizedBox(
                            widthFactor: percent.clamp(0.0, 1.0),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: AppPalette.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppPalette.primary,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: typography.cardTitleCompact.copyWith(
              color: hovered ? AppPalette.primary : AppPalette.textMain,
            ),
            child: Text(
              media.title.display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          if (nextEp != null && nextEp.episode > 0)
            Text(
              'Ep ${nextEp.episode} airing soon',
              style: const TextStyle(
                color: AppPalette.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              '${media.episodes ?? "?"} episodes',
              style: const TextStyle(color: AppPalette.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  final bool visible;
  final String label;
  final bool uiPerformanceMode;

  const _PlayOverlay({
    required this.visible,
    required this.label,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        // Zero-duration under Performant mode — snaps in/out instead of
        // fading, avoiding the saveLayer an interpolated opacity forces.
        duration: perfDuration(
          uiPerformanceMode,
          const Duration(milliseconds: 200),
        ),
        child: ColoredBox(
          color: AppPalette.black.withValues(alpha: 0.52),
          child: Center(
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.12),
              duration: perfDuration(
                uiPerformanceMode,
                const Duration(milliseconds: 250),
              ),
              curve: Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.primary,
                  // Fully-rounded stadium/pill button — 24 exceeds half
                  // this container's height to guarantee a full pill
                  // curve regardless of exact size, a different visual
                  // role than any of the tag/small/large tiers, so left
                  // as a plain literal.
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: uiPerformanceMode
                      ? null
                      : [
                          BoxShadow(
                            color: AppPalette.primary.withValues(alpha: 0.55),
                            blurRadius: 18,
                          ),
                        ],
                ),
                child: Text(
                  label,
                  // Left as a plain literal (12/w700/0.2 spacing) —
                  // doesn't match metaLabel or badgeLabel.
                  style: const TextStyle(
                    color: AppPalette.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
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
