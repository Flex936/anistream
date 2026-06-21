import 'dart:ui';
import 'package:flutter/material.dart';

import '../../data/anilist/models/anime.dart';
import '../../data/torrent/models/torrent.dart';
import '../../data/torrent/torrent_scraper_service.dart';
import '../../core/settings/settings_service.dart';
import '../../core/theme/app_palette.dart';
import '../theater/theater_screen.dart';

import 'widgets/hero_banner.dart';
import 'widgets/episode_tile.dart';

class AnimeDetailsScreen extends StatefulWidget {
  final Anime anime;
  final VoidCallback? onBack;

  const AnimeDetailsScreen({super.key, required this.anime, this.onBack});

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> {
  final TorrentScraperService _scraper = TorrentScraperService();
  final Map<int, Future<List<Torrent>>> _torrentFutures = {};

  int _expandedEpisode = -1;
  bool _autoPlayRecommended = false;

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
    () => _scraper.fetchTorrents(widget.anime, ep),
  );

  void _toggleEpisode(int ep) async {
    if (_isAutoPlaying) return;

    if (!_autoPlayRecommended) {
      setState(() => _expandedEpisode = _expandedEpisode == ep ? -1 : ep);
      return;
    }

    setState(() {
      _isAutoPlaying = true;
      _autoPlayTargetEpisode = ep;
      _expandedEpisode = -1;
    });

    try {
      final torrents = await _futureFor(ep);
      if (!mounted) return;

      if (torrents.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TheaterScreen(
              anime: widget.anime,
              episode: ep,
              torrent: torrents.first,
            ),
          ),
        );
      } else {
        setState(() => _expandedEpisode = ep);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _expandedEpisode = ep);
      }
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
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hPad = isMobile ? 24.0 : 48.0;

    return Scaffold(
      backgroundColor: AppPalette.base,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: HeroBanner(anime: widget.anime, onBack: widget.onBack),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 16),
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
              // ── FIXED: Added SafeArea wrapper for the bottom list to avoid the home bar ──
              SliverSafeArea(
                top: false,
                sliver: SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 12 : 20,
                    0,
                    isMobile ? 12 : 20,
                    64,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final ep = index + 1;
                      return EpisodeTile(
                        key: ValueKey(ep),
                        anime: widget.anime,
                        episodeNumber: ep,
                        isExpanded: _expandedEpisode == ep,
                        torrentFuture: _expandedEpisode == ep
                            ? _futureFor(ep)
                            : null,
                        onToggle: () => _toggleEpisode(ep),
                      );
                    }, childCount: _episodeCount),
                  ),
                ),
              ),
            ],
          ),

          if (_isAutoPlaying)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppPalette.primary,
                                ),
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
