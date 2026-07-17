import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_scope.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import 'widgets/anime_carousel.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const HomeScreen({super.key, this.onSelectAnime});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AnilistQueryService _api;

  late Future<List<Anime>> _trendingFuture;
  late Future<List<Anime>> _seasonPopularFuture;
  late Future<List<Anime>> _allTimePopularFuture;

  @override
  void initState() {
    super.initState();
    _api = AnilistQueryService();
    _trendingFuture = _api.getTrendingAnime(perPage: 15);
    _seasonPopularFuture = _api.getPopularThisSeason(perPage: 15);
    _allTimePopularFuture = _api.getAllTimePopular(perPage: 15);
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  void _loadTrending() {
    setState(() {
      _trendingFuture = _api.getTrendingAnime(perPage: 15);
    });
  }

  void _loadSeasonPopular() {
    setState(() {
      _seasonPopularFuture = _api.getPopularThisSeason(perPage: 15);
    });
  }

  void _loadAllTimePopular() {
    setState(() {
      _allTimePopularFuture = _api.getAllTimePopular(perPage: 15);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    return Scaffold(
      backgroundColor: AppPalette.base,
      body: SingleChildScrollView(
        // ── Both the 96px navbar clearance (previously a leading
        // SizedBox inside the Column) and the 48px bottom breathing room
        // now live in the scroll view's own `padding` instead of as
        // sibling widgets. This is dpad's documented convention for shelf
        // layouts — scroll-into-view and scrollPadding reason about the
        // scrollable's OWN padding as part of its content extent, so a
        // focused card at either end can actually be scrolled flush
        // against it, rather than stopping just short and leaving the
        // gap permanently on screen. ──
        padding: const EdgeInsets.only(top: 96, bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimeCarousel(
              title: 'Trending Now',
              future: _trendingFuture,
              uiPerformanceMode: uiPerformanceMode,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadTrending,
              autofocusFirst: true,
              memoryKey: 'home.trending',
            ),

            AnimeCarousel(
              title: 'Popular This Season',
              future: _seasonPopularFuture,
              uiPerformanceMode: uiPerformanceMode,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadSeasonPopular,
              memoryKey: 'home.season_popular',
            ),

            AnimeCarousel(
              title: 'All Time Popular',
              future: _allTimePopularFuture,
              uiPerformanceMode: uiPerformanceMode,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadAllTimePopular,
              memoryKey: 'home.all_time_popular',
            ),
          ],
        ),
      ),
    );
  }
}
