import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../data/anilist/models/media_list.dart';
import '../../../core/theme/app_palette.dart';

// ── Private Helpers ──

Color _statusColor(String? s) => switch (s) {
      'RELEASING' => AppPalette.statusReleasing,
      'FINISHED' => AppPalette.statusFinished,
      'CANCELLED' => AppPalette.statusCancelled,
      'HIATUS' => AppPalette.statusHiatus,
      _ => AppPalette.statusDefault,
    };

String _stripHtml(String? html) {
  if (html == null || html.isEmpty) return 'No synopsis available.';
  return html.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

// ════════════════════════════════════════════════════════════════════════════
//  HeroCard (16:9 Continue Watching Card)
// ════════════════════════════════════════════════════════════════════════════

class HeroCard extends StatefulWidget {
  final MediaListEntry entry;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const HeroCard({super.key, required this.entry, required this.onTap, required this.onHover});

  @override
  State<HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<HeroCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.entry.media;
    final progress = widget.entry.progress;
    final imgUrl = media.bannerImage ?? media.coverImage?.display;
    
    double percent = 0.0;
    if (media.episodes != null && media.episodes! > 0) {
      percent = progress / media.episodes!;
    } else if (progress > 0) {
      percent = 0.1;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) { setState(() => _hovered = true); widget.onHover(true); },
      onExit: (_) { setState(() => _hovered = false); widget.onHover(false); },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _hovered ? AppPalette.primary.withValues(alpha: 0.5) : AppPalette.border),
            boxShadow: _hovered ? [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.2), blurRadius: 20)] : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _PosterImage(url: imgUrl, hovered: _hovered),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [AppPalette.transparent, AppPalette.black.withValues(alpha: 0.9)],
                    ),
                  ),
                ),
                Center(
                  child: AnimatedScale(
                    scale: _hovered ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppPalette.primary.withValues(alpha: 0.8), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: AppPalette.white, size: 32),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16, left: 16, right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(media.title.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppPalette.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Continue Episode ${progress + 1}', style: const TextStyle(color: AppPalette.textLight, fontSize: 12)),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 3,
                    alignment: Alignment.centerLeft,
                    color: AppPalette.black,
                    child: FractionallySizedBox(
                      widthFactor: percent.clamp(0.0, 1.0),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppPalette.primary,
                          boxShadow: [BoxShadow(color: AppPalette.primary, blurRadius: 4)],
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
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ListCard (Dense layout for Planning/Watched list)
// ════════════════════════════════════════════════════════════════════════════

class ListCard extends StatefulWidget {
  final MediaListEntry entry;
  final bool showProgress;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const ListCard({super.key, required this.entry, required this.showProgress, required this.onTap, required this.onHover});

  @override
  State<ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<ListCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.entry.media;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) { setState(() => _hovered = true); widget.onHover(true); },
      onExit: (_) { setState(() => _hovered = false); widget.onHover(false); },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered ? AppPalette.surface.withValues(alpha: 0.8) : AppPalette.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _hovered ? AppPalette.primary.withValues(alpha: 0.5) : AppPalette.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 0.7,
                  child: _PosterImage(url: media.coverImage?.display, hovered: _hovered),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.title.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppPalette.textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: (media.status ?? 'UNKNOWN').replaceAll('_', ' '),
                            style: TextStyle(color: _statusColor(media.status), fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          const TextSpan(text: '  •  ', style: TextStyle(color: AppPalette.textMuted, fontSize: 12)),
                          TextSpan(
                            text: '★ ${(media.averageScore ?? 0) / 10}',
                            style: const TextStyle(color: AppPalette.accent, fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          TextSpan(text: '  •  ${media.episodes ?? "?"} EPS', style: const TextStyle(color: AppPalette.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!isMobile && media.genres != null && media.genres!.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        children: media.genres!.take(4).map((g) => Text('#$g', style: const TextStyle(color: AppPalette.primary, fontSize: 11))).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: Text(
                        _stripHtml(media.description),
                        maxLines: isMobile ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppPalette.textMuted, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  WatchlistCard (Upgraded Grid Layout for Planning/Watched Tab)
// ════════════════════════════════════════════════════════════════════════════

class WatchlistCard extends StatefulWidget {
  final MediaListEntry entry;
  final bool showProgress;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const WatchlistCard({super.key, required this.entry, required this.showProgress, required this.onTap, required this.onHover});

  @override
  State<WatchlistCard> createState() => _WatchlistCardState();
}

class _WatchlistCardState extends State<WatchlistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.entry.media;
    final progress = widget.entry.progress;
    final nextEp = media.nextAiringEpisode;

    double percent = 0.0;
    if (media.episodes != null && media.episodes! > 0) {
      percent = progress / media.episodes!;
    } else if (progress > 0) {
      percent = 0.1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) { setState(() => _hovered = true); widget.onHover(true); },
            onExit: (_) { setState(() => _hovered = false); widget.onHover(false); },
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _hovered ? AppPalette.primary.withValues(alpha: 0.55) : AppPalette.border),
                  boxShadow: _hovered ? [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.18), blurRadius: 24)] : const [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _PosterImage(url: media.coverImage?.display, hovered: _hovered),

                      if (widget.showProgress)
                        Positioned(
                          top: 8, right: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppPalette.black.withValues(alpha: 0.6),
                                  border: Border.all(color: AppPalette.white.withValues(alpha: 0.15)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.play_arrow_rounded, color: AppPalette.primary, size: 12),
                                    const SizedBox(width: 4),
                                    Text('EP $progress / ${media.episodes ?? "?"}', style: const TextStyle(color: AppPalette.textMain, fontSize: 10, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      _PlayOverlay(visible: _hovered, episode: progress + 1),

                      if (widget.showProgress)
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            height: 3,
                            alignment: Alignment.centerLeft,
                            color: AppPalette.black,
                            child: FractionallySizedBox(
                              widthFactor: percent.clamp(0.0, 1.0),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppPalette.primary,
                                  boxShadow: [BoxShadow(color: AppPalette.primary, blurRadius: 4)],
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
          ),
        ),

        const SizedBox(height: 10),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(color: _hovered ? AppPalette.primary : AppPalette.textMain, fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
          child: Text(media.title.display, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: 4),
        if (nextEp != null && nextEp.episode > 0)
          Text('Ep ${nextEp.episode} airing soon', style: const TextStyle(color: AppPalette.primary, fontSize: 11, fontWeight: FontWeight.w600))
        else
          Text('${media.episodes ?? "?"} episodes', style: const TextStyle(color: AppPalette.textMuted, fontSize: 11)),
      ],
    );
  }
}

// ── Private Reusable Card Helpers ──

class _PosterImage extends StatelessWidget {
  final String? url;
  final bool hovered;

  const _PosterImage({this.url, required this.hovered});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(color: AppPalette.surface, child: Center(child: Icon(Icons.image_not_supported_outlined, color: AppPalette.textMuted, size: 36)));
    }

    return AnimatedScale(
      scale: hovered ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppPalette.surface),
              AnimatedOpacity(opacity: frame != null ? 1.0 : 0.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut, child: child),
            ],
          );
        },
        errorBuilder: (_, _, _) => const ColoredBox(color: AppPalette.surface, child: Center(child: Icon(Icons.broken_image_outlined, color: AppPalette.textMuted, size: 36))),
      ),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  final bool visible;
  final int episode;

  const _PlayOverlay({required this.visible, required this.episode});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: ColoredBox(
          color: AppPalette.black.withValues(alpha: 0.52),
          child: Center(
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.12),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(color: AppPalette.primary, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.55), blurRadius: 18)]),
                child: Text('Play EP $episode', style: const TextStyle(color: AppPalette.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}