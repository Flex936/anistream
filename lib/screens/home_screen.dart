import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../widgets/anime_card.dart';
import '../services/anilist_api.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Private helpers
// ════════════════════════════════════════════════════════════════════════════

int _animeGridColumns(double width) {
  if (width < 600) return 2;
  if (width < 900) return 3;
  if (width < 1200) return 4;
  if (width < 1500) return 5;
  return 6;
}

// ════════════════════════════════════════════════════════════════════════════
//  HomeScreen
// ════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  // ── NEW: forwarded from AppShell so card taps stay inside the shell.
  final ValueChanged<Anime>? onSelectAnime;

  const HomeScreen({super.key, this.onSelectAnime});

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
    if (snapshot.connectionState != ConnectionState.done) {
      return const _LoadingPane();
    }
    if (snapshot.hasError) {
      return _ErrorPane(
        message: snapshot.error.toString(),
        onRetry: () => setState(_loadTrending),
      );
    }
    // ── CHANGED: pass onSelectAnime through to the grid.
    return _AnimeGrid(
      items: snapshot.data ?? const [],
      onSelectAnime: widget.onSelectAnime,
    );
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
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
      child: Text(
        title,
        style: const TextStyle(
          color: AppPalette.textMain,
          fontSize: 24,
          fontWeight: FontWeight.w600,
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
//  Anime grid
// ════════════════════════════════════════════════════════════════════════════

class _AnimeGrid extends StatelessWidget {
  final List<Anime> items;
  // ── NEW: forwarded straight to each AnimeCard.
  final ValueChanged<Anime>? onSelectAnime;

  const _AnimeGrid({required this.items, this.onSelectAnime});

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
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 20,
            mainAxisSpacing: 24,
            childAspectRatio: 0.55,
          ),
          itemCount: items.length,
          // ── CHANGED: onSelect wired up so taps route through AppShell.
          itemBuilder: (_, i) =>
              AnimeCard(anime: items[i], onSelect: onSelectAnime),
        );
      },
    );
  }
}
