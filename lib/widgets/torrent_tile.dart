import 'package:flutter/material.dart';

import '../services/torrent_scraper_service.dart';
import '../theme/app_palette.dart';

class TorrentTile extends StatefulWidget {
  final Torrent torrent;
  final bool isRecommended;
  final VoidCallback onStream;

  const TorrentTile({
    super.key,
    required this.torrent,
    this.isRecommended = false,
    required this.onStream,
  });

  @override
  State<TorrentTile> createState() => _TorrentTileState();
}

class _TorrentTileState extends State<TorrentTile> {
  bool _hovered = false;

  Color _seederColor(int n) {
    if (n > 100) return AppPalette.statusReleasing;
    if (n > 20) return AppPalette.accent;
    return AppPalette.statusCancelled;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.torrent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isRecommended) ...[
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: AppPalette.accent,
                size: 11,
              ),
              const SizedBox(width: 4),
              const Text(
                'RECOMMENDED',
                style: TextStyle(
                  color: AppPalette.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppPalette.primary.withValues(alpha: 0.09)
                  : widget.isRecommended
                  ? AppPalette.primary.withValues(alpha: 0.06)
                  : AppPalette.overlay,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? AppPalette.primary.withValues(alpha: 0.40)
                    : widget.isRecommended
                    ? AppPalette.primary.withValues(alpha: 0.22)
                    : AppPalette.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.title,
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
                          if (t.releaseGroup != 'Unknown')
                            _Pill(t.releaseGroup),
                          if (t.resolution != 'Unknown') _Pill(t.resolution),
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
                                t.size,
                                style: const TextStyle(
                                  color: AppPalette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '▲ ${t.seeders} Seeders',
                            style: TextStyle(
                              color: _seederColor(t.seeders),
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
                GestureDetector(
                  onTap: widget.onStream,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hovered
                          ? AppPalette.primary
                          : AppPalette.primary.withValues(alpha: 0.10),
                      boxShadow: _hovered
                          ? [
                              BoxShadow(
                                color: AppPalette.primary.withValues(
                                  alpha: 0.40,
                                ),
                                blurRadius: 14,
                              ),
                            ]
                          : const [],
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 22,
                      // FIXED HERE: Using AppPalette.white instead of Colors.white
                      color: _hovered ? AppPalette.white : AppPalette.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
