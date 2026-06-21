import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
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
    return Scaffold(
      backgroundColor: AppPalette.base,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 96),

            AnimeCarousel(
              title: 'Trending Now',
              future: _trendingFuture,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadTrending,
              autofocusFirst: true,
            ),

            AnimeCarousel(
              title: 'Popular This Season',
              future: _seasonPopularFuture,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadSeasonPopular,
            ),

            AnimeCarousel(
              title: 'All Time Popular',
              future: _allTimePopularFuture,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadAllTimePopular,
            ),
          ],
        ),
      ),
    );
  }
}
