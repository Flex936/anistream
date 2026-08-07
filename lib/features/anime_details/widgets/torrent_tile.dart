import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

class TorrentTile extends StatelessWidget {
  final Torrent torrent;
  final bool isRecommended;
  final bool uiPerformanceMode;
  final bool autofocus;
  final VoidCallback onStream;

  const TorrentTile({
    super.key,
    required this.torrent,
    this.isRecommended = false,
    this.uiPerformanceMode = false,
    this.autofocus = false,
    required this.onStream,
  });

  Color _seederColor(int n) {
    if (n > 100) return AppPalette.statusReleasing;
    if (n > 20) return AppPalette.accent;
    return AppPalette.statusCancelled;
  }

  @override
  Widget build(BuildContext context) {
    // Routed through the shared ResponsiveContext.isMobile extension.
    final isMobile = context.isMobile;

    // Pulled once at the top of build() rather than repeating
    // `context.appTypography`/`context.appRadii` at each call site below.
    final typography = context.appTypography;
    final radii = context.appRadii;

    return HoverFocusBuilder(
      autofocus: autofocus,
      onTap: onStream,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: hovered
              ? AppPalette.primary.withValues(alpha: 0.09)
              : isRecommended
              ? AppPalette.primary.withValues(alpha: 0.06)
              : AppPalette.overlay,
          // Matches AppRadii.small — this is a card/list-item shape per
          // DESIGN.md's "12px for list items" rule.
          borderRadius: BorderRadius.circular(radii.small),
          border: Border.all(
            color: hovered
                ? AppPalette.primary.withValues(alpha: 0.4)
                : isRecommended
                ? AppPalette.primary.withValues(alpha: 0.4)
                : AppPalette.border,
          ),
          boxShadow: (isRecommended && !uiPerformanceMode)
              ? [
                  BoxShadow(
                    color: AppPalette.primary.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radii.small),
          // Clip.hardEdge under Performant mode — see FrostedContainer's
          // doc comment for the rationale.
          clipBehavior: uiPerformanceMode ? Clip.hardEdge : Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRecommended)
                Container(
                  color: AppPalette.primary.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: AppPalette.primary,
                        size: 12,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'RECOMMENDED',
                        style: typography.badgeLabel.copyWith(
                          color: AppPalette.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            torrent.title,
                            style: typography.cardTitleCompact.copyWith(
                              color: AppPalette.textMain,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (torrent.releaseGroup != 'Unknown')
                                _Pill(torrent.releaseGroup),
                              if (torrent.resolution != 'Unknown')
                                _Pill(torrent.resolution),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.save_rounded,
                                    size: 12,
                                    color: AppPalette.textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  // Left as a plain literal — a muted,
                                  // regular-weight 12px label, distinct
                                  // from metaLabel (which is w600).
                                  Text(
                                    torrent.size,
                                    style: const TextStyle(
                                      color: AppPalette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '▲ ${torrent.seeders} Seeders',
                                style: typography.metaLabel.copyWith(
                                  color: _seederColor(torrent.seeders),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      width: isMobile ? 36 : 42,
                      height: isMobile ? 36 : 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hovered
                            ? AppPalette.primary
                            : AppPalette.primary.withValues(alpha: 0.1),
                        // Drops the hover glow under performance mode.
                        boxShadow: (hovered && !uiPerformanceMode)
                            ? [
                                BoxShadow(
                                  color: AppPalette.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 14,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: hovered ? AppPalette.white : AppPalette.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill(this.label);

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;
    final radii = context.appRadii;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppPalette.primary.withValues(alpha: 0.12),
        // Uses AppRadii.tag, the approved tier for small decorative
        // badges/pills.
        borderRadius: BorderRadius.circular(radii.tag),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: typography.badgeLabel.copyWith(color: AppPalette.primary),
      ),
    );
  }
}
