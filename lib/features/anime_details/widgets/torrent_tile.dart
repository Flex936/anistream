import 'package:flutter/material.dart';

import '../../../data/torrent/models/torrent.dart';
import '../../../core/theme/app_palette.dart';
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
    final isMobile = MediaQuery.sizeOf(context).width < 600;

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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hovered
                ? AppPalette.primary.withValues(alpha: 0.40)
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
          borderRadius: BorderRadius.circular(12),
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
                  child: const Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        color: AppPalette.primary,
                        size: 12,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'RECOMMENDED',
                        style: TextStyle(
                          color: AppPalette.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
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
                            style: const TextStyle(
                              color: AppPalette.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
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
                                style: TextStyle(
                                  color: _seederColor(torrent.seeders),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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
                            : AppPalette.primary.withValues(alpha: 0.10),
                        boxShadow:
                            (hovered &&
                                !uiPerformanceMode) // Drop hover glow if in performance mode
                            ? [
                                BoxShadow(
                                  color: AppPalette.primary.withValues(
                                    alpha: 0.40,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppPalette.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppPalette.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
