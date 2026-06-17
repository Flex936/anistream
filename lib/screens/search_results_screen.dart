import 'package:flutter/material.dart';

import '../services/anilist_api.dart';
import '../theme/app_palette.dart';
import '../widgets/anime_card.dart';

class SearchResultsScreen extends StatefulWidget {
  final String query;
  // ── NEW: forwarded from AppShell so card taps stay inside the shell.
  final ValueChanged<Anime>? onSelectAnime;

  const SearchResultsScreen({
    super.key,
    required this.query,
    this.onSelectAnime,
  });

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late final AnilistApiService _api;
  Future<List<Anime>>? _searchFuture;

  @override
  void initState() {
    super.initState();
    _api = AnilistApiService();
    _executeSearch();
  }

  @override
  void didUpdateWidget(SearchResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _executeSearch();
    }
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  void _executeSearch() {
    if (widget.query.trim().isEmpty) return;
    setState(() {
      _searchFuture = _api.searchAnime(widget.query);
    });
  }

  int _animeGridColumns(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    if (width < 1500) return 5;
    return 6;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
          child: Row(
            children: [
              Text(
                'Results for "${widget.query}"',
                style: const TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              if (_searchFuture != null)
                FutureBuilder(
                  future: _searchFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppPalette.primary,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),

        Expanded(
          child: _searchFuture == null
              ? const SizedBox.shrink()
              : FutureBuilder<List<Anime>>(
                  future: _searchFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppPalette.primary,
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Search failed: ${snapshot.error}',
                          style: const TextStyle(
                            color: AppPalette.statusCancelled,
                          ),
                        ),
                      );
                    }

                    final results = snapshot.data ?? [];
                    if (results.isEmpty) {
                      return const Center(
                        child: Text(
                          'No anime found.',
                          style: TextStyle(
                            color: AppPalette.textMuted,
                            fontSize: 15,
                          ),
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = _animeGridColumns(constraints.maxWidth);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: 20,
                                mainAxisSpacing: 24,
                                childAspectRatio: 0.55,
                              ),
                          itemCount: results.length,
                          // ── CHANGED: onSelect wired up so taps route through AppShell.
                          itemBuilder: (_, i) => AnimeCard(
                            anime: results[i],
                            onSelect: widget.onSelectAnime,
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
