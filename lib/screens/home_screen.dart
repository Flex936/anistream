import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../widgets/anime_card.dart';
import '../services/anilist_api.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Private helpers
// ════════════════════════════════════════════════════════════════════════════

/// Maps a viewport width to a grid column count, mirroring the Svelte
/// grid-cols-2 / md:grid-cols-4 / lg:grid-cols-5 / xl:grid-cols-6 classes.
int _animeGridColumns(double width) {
  if (width < 600) return 2;
  if (width < 900) return 3;
  if (width < 1200) return 4;
  if (width < 1500) return 5;
  return 6;
}

// ════════════════════════════════════════════════════════════════════════════
//  HomeScreen  (replaces DiscoveryView.svelte + App.svelte search logic)
// ════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AnilistApiService _api;
  late Future<List<Anime>> _trendingFuture;

  @override
  void initState() {
    super.initState();
    _api = AnilistApiService();
    _loadTrending();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  /// Assigns a fresh future. Calling setState(_loadTrending) retries the
  /// request and triggers FutureBuilder to reset to ConnectionState.waiting.
  void _loadTrending() {
    _trendingFuture = _api.getTrendingAnime(perPage: 24);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.base,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section heading — matches "Discover" h2 in DiscoveryView.svelte
          const _SectionHeader(title: 'Discover'),

          Expanded(
            child: FutureBuilder<List<Anime>>(
              future: _trendingFuture,
              builder: _buildContent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncSnapshot<List<Anime>> snapshot,
  ) {
    // Show spinner for every non-terminal connection state (none / waiting / active)
    if (snapshot.connectionState != ConnectionState.done) {
      return const _LoadingPane();
    }

    if (snapshot.hasError) {
      return _ErrorPane(
        message: snapshot.error.toString(),
        // setState(_loadTrending) replaces _trendingFuture and rebuilds
        onRetry: () => setState(_loadTrending),
      );
    }

    return _AnimeGrid(items: snapshot.data ?? const []);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Section header
// ════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Mirrors p-8 (32 px) padding from DiscoveryView.svelte
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
      child: Text(
        title,
        style: const TextStyle(
          color: AppPalette.textMain,
          fontSize: 24,
          fontWeight: FontWeight.w600, // font-semibold
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Loading pane
// ════════════════════════════════════════════════════════════════════════════

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
        strokeWidth: 2.5,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Error pane
// ════════════════════════════════════════════════════════════════════════════

class _ErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPane({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppPalette.textMuted,
            size: 52,
          ),
          const SizedBox(height: 16),
          const Text(
            'Could not load anime',
            style: TextStyle(
              color: AppPalette.textMain,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              style: const TextStyle(color: AppPalette.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.primary,
              side: const BorderSide(color: AppPalette.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Anime grid  (replaces the <div class="grid …"> in DiscoveryView.svelte)
// ════════════════════════════════════════════════════════════════════════════

class _AnimeGrid extends StatelessWidget {
  final List<Anime> items;
  const _AnimeGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No trending anime found.',
          style: TextStyle(color: AppPalette.textMuted, fontSize: 15),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _animeGridColumns(constraints.maxWidth);
        return GridView.builder(
          // p-8 (32 px) horizontal padding, 32 px bottom padding
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 20, // gap-6 ≈ 24 px; 20 px suits desktop density
            mainAxisSpacing: 24,
            // childAspectRatio = card_width / card_total_height.
            // A 2:3 poster (ratio 0.667) + ~66 px of text below ≈ 0.55.
            // Adjust this value if the typography height changes.
            childAspectRatio: 0.55,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => AnimeCard(anime: items[i]),
        );
      },
    );
  }
}
