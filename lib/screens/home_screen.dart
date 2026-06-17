import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../widgets/anime_card.dart';
import '../services/anilist_api.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const HomeScreen({super.key, this.onSelectAnime});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AnilistApiService _api;
  
  late Future<List<Anime>> _trendingFuture;
  late Future<List<Anime>> _seasonPopularFuture;
  late Future<List<Anime>> _allTimePopularFuture;

  @override
  void initState() {
    super.initState();
    _api = AnilistApiService();
    _loadTrending();
    _loadSeasonPopular();
    _loadAllTimePopular();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  // ── FIXED: Individual loading functions to prevent single rows from wiping out the whole screen ──
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
            const SizedBox(height: 16),
            
            _AnimeCarousel(
              title: 'Trending Now',
              future: _trendingFuture,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadTrending,
            ),
            
            _AnimeCarousel(
              title: 'Popular This Season',
              future: _seasonPopularFuture,
              onSelectAnime: widget.onSelectAnime,
              onRetry: _loadSeasonPopular,
            ),

            _AnimeCarousel(
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

// ════════════════════════════════════════════════════════════════════════════
//  Anime Carousel (Horizontal List)
// ════════════════════════════════════════════════════════════════════════════

class _AnimeCarousel extends StatelessWidget {
  final String title;
  final Future<List<Anime>> future;
  final ValueChanged<Anime>? onSelectAnime;
  final VoidCallback onRetry;

  const _AnimeCarousel({
    required this.title,
    required this.future,
    this.onSelectAnime,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Text(
            title,
            style: const TextStyle(
              color: AppPalette.textMain,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
        ),
        SizedBox(
          height: 330,
          child: FutureBuilder<List<Anime>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
                    strokeWidth: 2.5,
                  ),
                );
              }
              
              if (snapshot.hasError) {
                // Helpful trace to identify formatting issues if they happen on AniList's end
                debugPrint('[HomeScreen] Carousel Error inside "$title": ${snapshot.error}');
                return Center(
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.primary,
                      side: const BorderSide(color: AppPalette.primary),
                    ),
                  ),
                );
              }

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const Center(
                  child: Text('No anime found.', style: TextStyle(color: AppPalette.textMuted)),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                // FIXED: Resolved unnecessary underscores linting rule
                separatorBuilder: (context, index) => const SizedBox(width: 20),
                itemBuilder: (context, i) {
                  return SizedBox(
                    width: 170,
                    child: AnimeCard(
                      anime: items[i],
                      onSelect: onSelectAnime,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}