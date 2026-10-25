import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/torrent/models/torrent.dart';
import '../../data/torrent/torrent_scraper_service.dart';
import '../../shared/widgets/frosted_container.dart';
import '../theater/exo_theater_screen.dart';
import '../theater/services/streaming_controller_base.dart';
import '../theater/theater_screen.dart';
import 'widgets/anime_synopsis_section.dart';
import 'widgets/episode_tile.dart';
import 'widgets/hero_header_delegate.dart';
import 'widgets/torrent_search_modal.dart';

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

  bool _isFetchingSource = false;
  int _autoTorrentTargetEpisode = -1;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchProgress());
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

  /// A settled Future never re-resolves, so [forceRefresh] replaces the
  /// memoized entry to make a retry reach the network.
  Future<List<Torrent>> _futureFor(int ep, {bool forceRefresh = false}) {
    if (forceRefresh) {
      return _torrentFutures[ep] = _scraper.fetchTorrents(widget.anime, ep);
    }
    return _torrentFutures.putIfAbsent(
      ep,
      () => _scraper.fetchTorrents(widget.anime, ep),
    );
  }

  /// Episode-row tap: opens the torrent modal, or auto-streams the top result.
  void _toggleEpisode(int ep) {
    if (_isFetchingSource) return;

    final bool autoTorrentEnabled = SettingsScope.of(
      context,
      listen: false,
    ).settings.autoTorrentEnabled;

    if (!autoTorrentEnabled) {
      unawaited(_openTorrentModal(ep));
      return;
    }

    unawaited(_autoSelectTopTorrentAndStream(ep));
  }

  /// Streams [ep]'s top-scored torrent, or opens the modal on empty or error.
  Future<void> _autoSelectTopTorrentAndStream(int ep) async {
    setState(() {
      _isFetchingSource = true;
      _autoTorrentTargetEpisode = ep;
    });

    try {
      final torrents = await _futureFor(ep);
      if (!mounted) return;

      if (torrents.isNotEmpty) {
        await _streamTorrent(ep, torrents.first);
      } else if (mounted) {
        unawaited(_openTorrentModal(ep));
      }
    } catch (_) {
      if (mounted) unawaited(_openTorrentModal(ep));
    } finally {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isFetchingSource = false;
              _autoTorrentTargetEpisode = -1;
            });
          }
        });
      }
    }
  }

  /// Awaits the modal's pop result instead of pushing from a callback: an
  /// animated route leaves the Overlay asynchronously, so a same-stack push
  /// of the player screen would race it.
  Future<void> _openTorrentModal(int ep) async {
    final bool uiPerformanceMode = SettingsScope.of(
      context,
      listen: false,
    ).settings.uiPerformanceMode;

    final torrent = await TorrentSearchModal.show(
      context: context,
      episodeNumber: ep,
      torrentsFuture: _futureFor(ep),
      onRetry: () => _futureFor(ep, forceRefresh: true),
      uiPerformanceMode: uiPerformanceMode,
    );

    if (torrent != null && mounted) {
      unawaited(_streamTorrent(ep, torrent));
    }
  }

  /// Pushes the player screen, then refreshes AniList progress; never pops
  /// anything itself. See ARCHITECTURE.md § 9.
  Future<void> _streamTorrent(int ep, Torrent torrent) async {
    final bool useExoPlayer = SettingsScope.of(
      context,
      listen: false,
    ).settings.useExoPlayer;

    // Next-episode request (autoFetch/manualPick) this screen resolves itself.
    (int, NextEpisodeTransitionMode)? pendingDelegate;

    if (useExoPlayer) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ExoTheaterScreen(
            anime: widget.anime,
            episode: ep,
            torrent: torrent,
          ),
        ),
      );
    } else {
      BaseStreamingController? resumeController;
      Duration? resumePosition;

      while (true) {
        final result = await Navigator.push<TheaterExitResult?>(
          context,
          MaterialPageRoute<TheaterExitResult?>(
            builder: (_) => TheaterScreen(
              anime: widget.anime,
              episode: ep,
              magnetUri: torrent.magnetLink,
              totalEpisodes: _episodeCount,
              resumeController: resumeController,
              resumePosition: resumePosition,
            ),
          ),
        );

        if (result == null) break;

        if (result is TheaterRestartRequest) {
          resumeController = result.resumeController;
          resumePosition = result.resumePosition;
          continue;
        }

        if (result is TheaterNextEpisodeRequest) {
          if (result.mode == NextEpisodeTransitionMode.instantHandoff) {
            ep = result.nextEpisode;
            torrent = result.prewarmedTorrent!;
            resumeController = result.prewarmedController;
            resumePosition = Duration.zero;
            continue;
          }
          pendingDelegate = (result.nextEpisode, result.mode);
        }

        break;
      }
    }

    if (mounted) {
      await _fetchProgress();
    }

    if (pendingDelegate != null && mounted) {
      final (nextEpisode, mode) = pendingDelegate;
      if (mode == NextEpisodeTransitionMode.autoFetch) {
        unawaited(_autoSelectTopTorrentAndStream(nextEpisode));
      } else {
        unawaited(_openTorrentModal(nextEpisode));
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
    final bool isMobile = MediaQuery.sizeOf(context).width < 600;
    final double hPad = isMobile ? 24.0 : 48.0;
    final settings = SettingsScope.of(context).settings;
    final bool uiPerformanceMode = settings.uiPerformanceMode;
    final materials = context.appMaterials;

    return Scaffold(
      backgroundColor: AppPalette.base,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: HeroHeaderDelegate(
                  anime: widget.anime,
                  onBack: widget.onBack,
                  uiPerformanceMode: uiPerformanceMode,
                ),
              ),
              SliverToBoxAdapter(
                child: AnimeSynopsisSection(anime: widget.anime),
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
                        episodeNumber: ep,
                        userProgress: _userProgress,
                        isUpNext: isUpNext,
                        isCurrentlyLoading:
                            _isFetchingSource &&
                            _autoTorrentTargetEpisode == ep,
                        uiPerformanceMode: uiPerformanceMode,
                        onToggle: () => _toggleEpisode(ep),
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
                  final overlayContent = FrostedContainer(
                    uiPerformanceMode: uiPerformanceMode,
                    sigma: materials.standard,
                    child: Container(
                      color: AppPalette.base.withValues(
                        alpha: uiPerformanceMode ? 0.95 : 0.75,
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
                              'Finding best source for Episode $_autoTorrentTargetEpisode...',
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
                  );

                  return Opacity(opacity: opacity, child: overlayContent);
                },
              ),
            ),
        ],
      ),
    );
  }
}
