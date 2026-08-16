import 'package:flutter/material.dart';

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

    // No Scaffold: HomeScreen is only ever built by
    // NavigationController.buildHome, always rendered inside AppShell's
    // own Scaffold (app_shell.dart), which already paints the identical
    // AppPalette.base background beneath it.
    return SingleChildScrollView(
      // Both the 96px navbar clearance and the 48px bottom breathing
      // room live in the scroll view's own `padding` rather than as
      // sibling widgets — dpad's shelf-layout convention treats
      // scroll-into-view and scrollPadding as part of the scrollable's
      // own content extent, so a focused card at either end can be
      // scrolled flush against it instead of stopping just short.
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
    );
  }
}
