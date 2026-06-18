import 'dart:ui';
import 'package:flutter/material.dart';

import '../services/anilist_query_service.dart';
import '../services/torrent_scraper_service.dart';
import '../theme/app_palette.dart';
import '../widgets/episode_tile.dart';
import '../widgets/network_image.dart';

// ════════════════════════════════════════════════════════════════════════════
//  File-private helpers
// ════════════════════════════════════════════════════════════════════════════

String _stripHtml(String? html) {
  if (html == null || html.isEmpty) return 'No synopsis available.';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

Color _statusColor(String? s) => switch (s) {
      'RELEASING' => AppPalette.statusReleasing,
      'FINISHED' => AppPalette.statusFinished,
      'CANCELLED' => AppPalette.statusCancelled,
      'HIATUS' => AppPalette.statusHiatus,
      _ => AppPalette.statusDefault,
    };

String _formatStatus(String? s) => (s ?? 'UNKNOWN').replaceAll('_', ' ');

// ════════════════════════════════════════════════════════════════════════════
//  AnimeDetailsScreen
// ════════════════════════════════════════════════════════════════════════════

class AnimeDetailsScreen extends StatefulWidget {
  final Anime anime;
  final VoidCallback? onBack;

  const AnimeDetailsScreen({super.key, required this.anime, this.onBack});

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> {
  final TorrentScraperService _scraper = TorrentScraperService();
  int _expandedEpisode = -1;
  final Map<int, Future<List<Torrent>>> _torrentFutures = {};

  int get _episodeCount {
    if (widget.anime.status == 'RELEASING' &&
        widget.anime.nextAiringEpisode != null) {
      return widget.anime.nextAiringEpisode!.episode - 1;
    }
    return widget.anime.episodes ?? 12;
  }

  Future<List<Torrent>> _futureFor(int ep) => _torrentFutures.putIfAbsent(
        ep,
        () => _scraper.fetchTorrents(widget.anime.title, ep),
      );

  void _toggleEpisode(int ep) => setState(() {
        _expandedEpisode = _expandedEpisode == ep ? -1 : ep;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.base,
      // ── FIXED: Removed the outer Stack. The scroll view now owns the screen ──
      body: CustomScrollView(
        slivers: [
          // 1. The Edge-to-Edge Hero Banner
          SliverToBoxAdapter(
            // ── FIXED: Passed the onBack function directly into the Hero ──
            child: _HeroSection(anime: widget.anime, onBack: widget.onBack),
          ),

          // 2. The Episode List Header
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(48, 16, 48, 16),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Text(
                    'Episodes',
                    style: TextStyle(
                      color: AppPalette.textMain,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppPalette.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '$_episodeCount',
                      style: const TextStyle(
                        color: AppPalette.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. The Frameless Episode List
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 64),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final ep = index + 1;
                  return EpisodeTile(
                    key: ValueKey(ep),
                    episodeNumber: ep,
                    isExpanded: _expandedEpisode == ep,
                    torrentFuture:
                        _expandedEpisode == ep ? _futureFor(ep) : null,
                    onToggle: () => _toggleEpisode(ep),
                  );
                },
                childCount: _episodeCount,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _HeroSection (The Apple TV / Netflix Vibe)
// ════════════════════════════════════════════════════════════════════════════

class _HeroSection extends StatelessWidget {
  final Anime anime;
  final VoidCallback? onBack; // ── ADDED ──

  const _HeroSection({required this.anime, this.onBack});

  @override
  Widget build(BuildContext context) {
    // Prefer the ultra-wide banner, fallback to cover image
    final bannerUrl = anime.bannerImage ?? anime.coverImage?.extraLarge;
    final posterUrl = anime.coverImage?.extraLarge;

    return SizedBox(
      width: double.infinity,
      height: 600, // Immersive height
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 1: Background Image ──
          if (bannerUrl != null) AppNetworkImage(url: bannerUrl),

          // ── Layer 2: Seamless Fade Gradient ──
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppPalette.base.withValues(alpha: 0.1), // Top: Mostly clear
                  AppPalette.base.withValues(alpha: 0.7), // Mid: Darkening
                  AppPalette.base,                        // Bottom: Solid background
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── Layer 2.5: The Anchored Back Button ──
          Positioned(
            top: 96,
            left: 48, // ── FIXED: Perfectly aligns with the poster below it ──
            child: _FloatingNavBar(onBack: onBack),
          ),

          // ── Layer 3: Organic Content Layout ──
          Positioned(
            bottom: 24,
            left: 48,
            right: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Floating Poster with soft shadow
                if (posterUrl != null)
                  Container(
                    width: 220,
                    height: 330,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppPalette.black.withValues(alpha: 0.6),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AppNetworkImage(url: posterUrl),
                    ),
                  ),

                const SizedBox(width: 48),

                // Floating Meta Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        anime.title.display,
                        style: const TextStyle(
                          color: AppPalette.textMain,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          letterSpacing: -1.0,
                        ),
                      ),
                      if (anime.title.english != null &&
                          anime.title.english != anime.title.romaji) ...[
                        const SizedBox(height: 12),
                        Text(
                          anime.title.english!,
                          style: const TextStyle(
                            color: AppPalette.textMuted,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MetaChip(
                            label: _formatStatus(anime.status),
                            color: _statusColor(anime.status),
                          ),
                          if (anime.episodes != null)
                            _MetaChip(
                              label: '${anime.episodes} Episodes',
                              color: AppPalette.textLight,
                            ),
                          if (anime.averageScore != null)
                            _MetaChip(
                              label:
                                  '★ ${(anime.averageScore! / 10).toStringAsFixed(1)} Score',
                              color: AppPalette.accent,
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _stripHtml(anime.description),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppPalette.textMuted,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _FloatingNavBar (Minimal frosted glass pill)
// ════════════════════════════════════════════════════════════════════════════

class _FloatingNavBar extends StatefulWidget {
  final VoidCallback? onBack;
  const _FloatingNavBar({this.onBack});

  @override
  State<_FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<_FloatingNavBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (widget.onBack != null) {
            widget.onBack!();
          } else {
            Navigator.maybePop(context);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _hovered
                    ? AppPalette.white.withValues(alpha: 0.15)
                    : AppPalette.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: AppPalette.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSlide(
                    offset: _hovered ? const Offset(-0.15, 0) : Offset.zero,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: AppPalette.textMain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Back',
                    style: TextStyle(
                      color: AppPalette.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _MetaChip (Refined padding for the new layout)
// ════════════════════════════════════════════════════════════════════════════

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}