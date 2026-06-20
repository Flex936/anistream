import 'package:flutter/material.dart';

import '../../../data/torrent/models/torrent.dart';
import '../../../core/theme/app_palette.dart';

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
    final isMobile = MediaQuery.of(context).size.width < 600;

    return FocusableActionDetector(
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _hovered = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onStream();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        // The recommended box now encompasses the entire tile
        decoration: BoxDecoration(
          color: _hovered
              ? AppPalette.primary.withValues(alpha: 0.09)
              : widget.isRecommended
              ? AppPalette.primary.withValues(alpha: 0.06)
              : AppPalette.overlay,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered
                ? AppPalette.primary.withValues(alpha: 0.40)
                : widget.isRecommended
                ? AppPalette.primary.withValues(
                    alpha: 0.4,
                  ) // Glows more when recommended
                : AppPalette.border,
          ),
          boxShadow: widget.isRecommended
              ? [
                  BoxShadow(
                    color: AppPalette.primary.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Recommended Header Bar ──
              if (widget.isRecommended)
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

              // ── Main Content ──
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
                              if (t.resolution != 'Unknown')
                                _Pill(t.resolution),
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
                        curve: Curves.easeOutCubic,
                        width: isMobile ? 36 : 42,
                        height: isMobile ? 36 : 42,
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
                          color: _hovered
                              ? AppPalette.white
                              : AppPalette.primary,
                        ),
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
