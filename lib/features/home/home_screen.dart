import 'package:flutter/material.dart';

import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../shell/widgets/navbar.dart';
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
        // Top clearance matches AniStreamNavBar's real rendered height
        // (its nominal height plus the device's own top system-UI
        // inset) so content never starts underneath the status bar or
        // the navbar itself. Bottom padding adds the device's bottom
        // inset on top of the fixed breathing-room constant so the last
        // shelf isn't obscured by a gesture bar / 3-button nav bar.
        // Both insets are 0 on Android TV and desktop, so this padding
        // collapses back to the original fixed values there.
        padding: EdgeInsets.only(
          top: AniStreamNavBar.barHeight + MediaQuery.paddingOf(context).top,
          bottom: 48 + MediaQuery.paddingOf(context).bottom,
        ),
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
