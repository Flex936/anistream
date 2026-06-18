import 'dart:ui';
import 'package:flutter/material.dart';

import '../services/anilist_query_service.dart';
import '../services/torrent_scraper_service.dart';
import '../services/settings_service.dart';
import '../theme/app_palette.dart';
import '../widgets/episode_tile.dart';
import '../widgets/network_image.dart';
import '../screens/theater_screen.dart';

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
  
  bool _autoPlayRecommended = false;
  
  // ── Locking states to prevent double-click crashes ──
  bool _isAutoPlaying = false;
  int _autoPlayTargetEpisode = -1;

  @override
  void initState() {
    super.initState();
    SettingsService().load().then((s) {
      if (mounted) setState(() => _autoPlayRecommended = s.autoPlayRecommended);
    });
  }

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

  void _toggleEpisode(int ep) async {
    // ── Immediately abort if we are already attempting to load an episode ──
    if (_isAutoPlaying) return;

    // Normal behavior (Auto-play OFF)
    if (!_autoPlayRecommended) {
      setState(() {
        _expandedEpisode = _expandedEpisode == ep ? -1 : ep;
      });
      return;
    }

    // ── Auto-Play Behavior ──
    setState(() {
      _isAutoPlaying = true;
      _autoPlayTargetEpisode = ep;
      _expandedEpisode = -1; // Force the dropdown to stay closed
    });

    try {
      final torrents = await _futureFor(ep);
      if (!mounted) return;
      
      if (torrents.isNotEmpty) {
        // Wait for the user to return from the video player before unlocking
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TheaterScreen(
              episode: ep,
              torrent: torrents.first, // The highest rated torrent
            ),
          ),
        );
      } else {
        // If no torrents are found, gracefully fallback and expand the 
        // dropdown so they can see the "No releases found" text.
        setState(() => _expandedEpisode = ep);
      }
    } catch (_) {
      // On scrape error, expand the dropdown to show the error message
      setState(() => _expandedEpisode = ep);
    } finally {
      if (mounted) {
        setState(() {
          _isAutoPlaying = false;
          _autoPlayTargetEpisode = -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.base,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _HeroSection(anime: widget.anime, onBack: widget.onBack),
              ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppPalette.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppPalette.primary.withValues(alpha: 0.25)),
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
                        torrentFuture: _expandedEpisode == ep ? _futureFor(ep) : null,
                        onToggle: () => _toggleEpisode(ep),
                      );
                    },
                    childCount: _episodeCount,
                  ),
                ),
              ),
            ],
          ),

          // ── Beautiful frosted glass overlay for the Auto-Play scraper ──
          if (_isAutoPlaying)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 250),
                builder: (context, opacity, child) {
                  return Opacity(
                    opacity: opacity,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: AppPalette.base.withValues(alpha: 0.75),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Finding best source for Episode $_autoPlayTargetEpisode...',
                                style: const TextStyle(
                                  color: AppPalette.textMain,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
  final VoidCallback? onBack;

  const _HeroSection({required this.anime, this.onBack});

  @override
  Widget build(BuildContext context) {
    final bannerUrl = anime.bannerImage ?? anime.coverImage?.extraLarge;
    final posterUrl = anime.coverImage?.extraLarge;

    return SizedBox(
      width: double.infinity,
      height: 600, 
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bannerUrl != null) AppNetworkImage(url: bannerUrl),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppPalette.base.withValues(alpha: 0.1), 
                  AppPalette.base.withValues(alpha: 0.7), 
                  AppPalette.base,                        
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          Positioned(
            top: 96,
            left: 48, 
            child: _FloatingNavBar(onBack: onBack),
          ),

          Positioned(
            bottom: 24,
            left: 48,
            right: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
//  _FloatingNavBar 
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
//  _MetaChip 
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