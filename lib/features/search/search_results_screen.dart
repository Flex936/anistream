import 'package:flutter/material.dart';

import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_scope.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/utils/responsive_grid.dart';
import 'widgets/search_filter_panel.dart';

class SearchResultsScreen extends StatefulWidget {
  final String query;
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
  late final AnilistQueryService _api;
  Future<List<Anime>>? _searchFuture;

  int _minScore = 0;
  String _selectedStatus = 'ANY';
  late double _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year.toDouble() + 1;
    _api = AnilistQueryService();
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
    if (widget.query.trim().isEmpty) {
      if (mounted) {
        setState(() => _searchFuture = null);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _searchFuture = _api.searchAnime(
          widget.query,
          minScore: _minScore > 0 ? _minScore : null,
          status: _selectedStatus == 'ANY' ? null : _selectedStatus,
          year: _selectedYear > DateTime.now().year
              ? null
              : _selectedYear.toInt(),
        );
      });
    }
  }

  void _openFilterDrawer() {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    final panel = SearchFilterPanel(
      initialMinScore: _minScore,
      initialStatus: _selectedStatus,
      initialYear: _selectedYear,
      uiPerformanceMode: uiPerformanceMode,
      onApply: (minScore, status, year) {
        setState(() {
          _minScore = minScore;
          _selectedStatus = status;
          _selectedYear = year;
        });
        _executeSearch();
      },
    );

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => panel,
      );
    } else {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Filters',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) {
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 380, height: double.infinity, child: panel),
          );
        },
        transitionBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.trim().isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 96),

          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
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
                const SizedBox(width: 16),

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
                            valueColor: AlwaysStoppedAnimation(
                              AppPalette.primary,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                const Spacer(),

                OutlinedButton.icon(
                  onPressed: _openFilterDrawer,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.textMain,
                    side: const BorderSide(color: AppPalette.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_searchFuture != null)
            FutureBuilder<List<Anime>>(
              future: _searchFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.5,
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(AppPalette.primary),
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  final err = snapshot.error;
                  final msg = err is AnilistException
                      ? err.message
                      : 'An unexpected error occurred.';
                  return SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.5,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppPalette.statusCancelled,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            msg,
                            style: const TextStyle(
                              color: AppPalette.textMuted,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final results = snapshot.data ?? [];
                if (results.isEmpty) {
                  return SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.5,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            color: AppPalette.textMuted,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No anime found. Try adjusting your filters.',
                            style: TextStyle(
                              color: AppPalette.textMuted,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    // ── Shared with WatchlistScreen's portrait grid instead
                    // of a locally duplicated breakpoint table. ──
                    final cols = verticalGridColumns(constraints.maxWidth);
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 24,
                        childAspectRatio: 0.55,
                      ),
                      itemCount: results.length,
                      itemBuilder: (_, i) => AnimeCard(
                        anime: results[i],
                        onSelect: widget.onSelectAnime,
                        autofocus: i == 0,
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}
