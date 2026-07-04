import 'dart:ui';
import 'package:flutter/material.dart';

import '../../data/anilist/models/anime.dart';
import '../../data/anilist/anilist_query_service.dart';
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

  int? _userProgress;
  int _expandedEpisode = -1;

  bool _autoPlayEnabled = false;
  bool _isFetchingSource = false;
  int _autoPlayTargetEpisode = -1;

  // ── UI Performance State ──
  bool _uiPerformanceMode = false;

  @override
  void initState() {
    super.initState();
    SettingsService().load().then((s) {
      if (mounted) {
        setState(() {
          _autoPlayEnabled = s.autoPlayEnabled;
          _uiPerformanceMode = s.uiPerformanceMode;
        });
      }
    });

    _fetchProgress();
  }

  Future<void> _fetchProgress() async {
    final progress = await AnilistQueryService().getMediaProgress(
      widget.anime.id,
    );
    if (!mounted || progress == null) return;
    setState(() => _userProgress = progress);
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
    if (_isFetchingSource) return;

    if (!_autoPlayEnabled) {
      setState(() => _expandedEpisode = _expandedEpisode == ep ? -1 : ep);
      return;
    }

    setState(() {
      _isFetchingSource = true;
      _autoPlayTargetEpisode = ep;
      _expandedEpisode = -1;
    });

    try {
      final torrents = await _futureFor(ep);
      if (!mounted) return;

      if (torrents.isNotEmpty) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TheaterScreen(
              anime: widget.anime,
              episode: ep,
              torrent: torrents.first,
            ),
          ),
        );
        if (mounted) {
          _fetchProgress();
        }
      } else {
        if (mounted) setState(() => _expandedEpisode = ep);
      }
    } catch (_) {
      if (mounted) setState(() => _expandedEpisode = ep);
    } finally {
      if (mounted) {
        // ── Safely teardown the loading overlay after the frame ──
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isFetchingSource = false;
              _autoPlayTargetEpisode = -1;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _scraper.dispose();
    super.dispose();
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
                child: HeroBanner(
                  anime: widget.anime,
                  onBack: widget.onBack,
                  uiPerformanceMode: _uiPerformanceMode,
                ),
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
                      final isUpNext =
                          _userProgress != null &&
                          ep == (_userProgress! + 1) &&
                          ep <= _episodeCount;

                      return EpisodeTile(
                        key: ValueKey(ep),
                        anime: widget.anime,
                        episodeNumber: ep,
                        isExpanded: _expandedEpisode == ep,
                        userProgress: _userProgress,
                        isUpNext: isUpNext,
                        isAutoPlayEnabled: _autoPlayEnabled,
                        isCurrentlyLoading:
                            _isFetchingSource && _autoPlayTargetEpisode == ep,
                        uiPerformanceMode: _uiPerformanceMode,
                        torrentFuture: _expandedEpisode == ep
                            ? _futureFor(ep)
                            : null,
                        onToggle: () => _toggleEpisode(ep),
                        onReturnFromTheater: _fetchProgress,
                      );
                    }, childCount: _episodeCount),
                  ),
                ),
              ),
            ],
          ),

          if (_isFetchingSource)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                builder: (context, opacity, child) {
                  Widget overlayContent = Container(
                    color: AppPalette.base.withValues(
                      alpha: _uiPerformanceMode ? 0.95 : 0.75,
                    ),
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
                  );

                  if (!_uiPerformanceMode) {
                    overlayContent = BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: overlayContent,
                    );
                  }

                  return Opacity(opacity: opacity, child: overlayContent);
                },
              ),
            ),
        ],
      ),
    );
  }
}
