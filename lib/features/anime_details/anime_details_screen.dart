import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/torrent/models/torrent.dart';
import '../../data/torrent/torrent_scraper_service.dart';
import '../../shared/utils/theater_session.dart';
import '../../shared/widgets/frosted_container.dart';
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
  int _autoPlayTargetEpisode = -1;

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

  Future<List<Torrent>> _futureFor(int ep) => _torrentFutures.putIfAbsent(
    ep,
    () => _scraper.fetchTorrents(widget.anime, ep),
  );

  /// Tap entry point for an episode row. With autoplay off, this always
  /// opens [TorrentSearchModal]. With autoplay on, it silently tries the
  /// top result first, falling back to the same modal on either an empty
  /// result or a thrown exception.
  void _toggleEpisode(int ep) {
    if (_isFetchingSource) return;

    final bool autoPlayEnabled = SettingsScope.of(
      context,
      listen: false,
    ).settings.autoPlayEnabled;

    if (!autoPlayEnabled) {
      unawaited(_openTorrentModal(ep));
      return;
    }

    unawaited(_autoPlayEpisode(ep));
  }

  Future<void> _autoPlayEpisode(int ep) async {
    setState(() {
      _isFetchingSource = true;
      _autoPlayTargetEpisode = ep;
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
              _autoPlayTargetEpisode = -1;
            });
          }
        });
      }
    }
  }

  /// Opens [TorrentSearchModal] for [ep], reusing the same memoized
  /// [Future] `_futureFor` already produces — including one that's
  /// already settled by the time this is called (e.g. autoplay's
  /// fallback path), so the modal never triggers a second network
  /// request for a search that already ran.
  ///
  /// Awaits the modal's own pop result rather than handing it a callback
  /// that pops and immediately pushes TheaterScreen: [TorrentSearchModal]
  /// is an animated route, so popping it doesn't remove it from the
  /// Overlay synchronously. Pushing TheaterScreen in the same call stack
  /// as that pop races the two routes' Overlay entries against each
  /// other. Awaiting [TorrentSearchModal.show] defers the push to a later
  /// microtask, after the modal's own exit has actually resolved.
  Future<void> _openTorrentModal(int ep) async {
    final bool uiPerformanceMode = SettingsScope.of(
      context,
      listen: false,
    ).settings.uiPerformanceMode;

    final torrent = await TorrentSearchModal.show(
      context: context,
      episodeNumber: ep,
      torrentsFuture: _futureFor(ep),
      uiPerformanceMode: uiPerformanceMode,
    );

    if (torrent != null && mounted) {
      unawaited(_streamTorrent(ep, torrent));
    }
  }

  /// Streams [torrent] for episode [ep] via the shared
  /// [runTheaterSession] helper — including transparently following any
  /// freeze-recovery restarts it re-pushes through, see that function's
  /// own doc comment — then refreshes AniList progress once the whole
  /// viewing session genuinely ends. Deliberately does NOT pop anything
  /// itself — it's called both from [_openTorrentModal] (once the
  /// modal's own pop has already resolved) AND from
  /// [_autoPlayEpisode]'s direct success path (where no modal was ever
  /// opened).
  Future<void> _streamTorrent(int ep, Torrent torrent) async {
    await runTheaterSession(
      context: context,
      anime: widget.anime,
      episode: ep,
      magnetUri: torrent.magnetLink,
      displayTitle: widget.anime.title.display,
    );

    if (mounted) {
      await _fetchProgress();
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
                            _isFetchingSource && _autoPlayTargetEpisode == ep,
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
