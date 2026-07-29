import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

class TorrentTile extends StatelessWidget {
  final Torrent torrent;
  final bool isRecommended;
  final bool uiPerformanceMode;
  final VoidCallback onStream;

  const TorrentTile({
    super.key,
    required this.torrent,
    this.isRecommended = false,
    this.uiPerformanceMode = false,
    required this.onStream,
  });

  Color _seederColor(int n) {
    if (n > 100) return AppPalette.statusReleasing;
    if (n > 20) return AppPalette.accent;
    return AppPalette.statusCancelled;
  }

  @override
  Widget build(BuildContext context) {
    // ── Routed through the shared
    // ResponsiveContext.isMobile extension. ──
    final isMobile = context.isMobile;

    // ── Pulling both token sets once at the top of
    // build() rather than repeating `context.appTypography`/
    // `context.appRadii` at each call site below. ──
    final typography = context.appTypography;
    final radii = context.appRadii;

    return HoverFocusBuilder(
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
          // ── Was BorderRadius.circular(12) hardcoded — matches
          // AppRadii.small exactly (this is a card/list-item shape per
          // DESIGN.md's own "12px for list items" rule), so this is a
          // pure token substitution with no visual change. ──
          borderRadius: BorderRadius.circular(radii.small),
          border: Border.all(
            color: hovered
                ? AppPalette.primary.withValues(alpha: 0.4)
                : isRecommended
                ? AppPalette.primary.withValues(alpha: 0.4)
                : AppPalette.border,
          ),
          // ── Drops the shadow if performance mode is enabled ──
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
          // ── Clip.hardEdge under Performant mode — see
          // FrostedContainer's doc comment for the rationale. This clip
          // wasn't routed through FrostedContainer at all previously. ──
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
                      // ── Was TextStyle(fontSize: 10, fontWeight: w800,
                      // letterSpacing: 1.0) — part of the approved
                      // badgeLabel convergence cluster. Only visual
                      // delta: letterSpacing 1.0 -> 0.5 (badgeLabel's
                      // converged value). Size/weight unchanged. ──
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
                          // ── Was TextStyle(fontSize: 13, fontWeight:
                          // w500, height: 1.4) — part of the approved
                          // cardTitleCompact convergence cluster. Visual
                          // delta: fontWeight w500 -> w600 (converged
                          // value); height 1.4 -> 1.35. ──
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
                                  // ── Left as a plain literal — this is
                                  // a muted, regular-weight 12px label,
                                  // not a match for any identified
                                  // duplicate cluster (metaLabel is
                                  // w600). Forcing it into metaLabel
                                  // would incorrectly bump its weight. ──
                                  Text(
                                    torrent.size,
                                    style: const TextStyle(
                                      color: AppPalette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              // ── Was TextStyle(fontSize: 12, fontWeight:
                              // w600) inline — exact match for metaLabel,
                              // pure token substitution, no visual change. ──
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
                        boxShadow:
                            (hovered &&
                                !uiPerformanceMode) // Drop hover glow if in performance mode
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
        // ── Was BorderRadius.circular(4) — nudged up to AppRadii.tag
        // (6), the approved tier for small decorative badges/pills.
        // Small, deliberate visual convergence rather than a pure
        // refactor. ──
        borderRadius: BorderRadius.circular(radii.tag),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.28)),
      ),
      // ── Was TextStyle(fontSize: 10, fontWeight: w700, letterSpacing:
      // 0.3) — part of the approved badgeLabel convergence cluster.
      // Visual delta: fontWeight w700 -> w800; letterSpacing 0.3 -> 0.5. ──
      child: Text(
        label,
        style: typography.badgeLabel.copyWith(color: AppPalette.primary),
      ),
    );
  }
}
