import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../shared/widgets/anime_card.dart';
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
    // Routed through the shared ResponsiveContext.isMobile extension,
    // matching the breakpoint watchlist_screen.dart/responsive_grid.dart
    // standardize on.
    final isMobile = context.isMobile;
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
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => panel,
        ),
      );
    } else {
      unawaited(
        showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Filters',
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, _, _) {
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 380,
                height: double.infinity,
                child: panel,
              ),
            );
          },
          transitionBuilder: (context, animation, _, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.trim().isEmpty) return const SizedBox.shrink();

    final typography = context.appTypography;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top clearance is just the device's own top system-UI inset —
          // Scaffold's extendBodyBehindAppBar injects an inner MediaQuery
          // for the body whose padding.top already equals the navbar's
          // full rendered height, so no separate navbar-height term is
          // needed here. 0 additional inset on Android TV/desktop.
          SizedBox(height: MediaQuery.paddingOf(context).top),

          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            child: Row(
              children: [
                Text(
                  'Results for "${widget.query}"',
                  style: typography.sectionTitle.copyWith(
                    color: AppPalette.textMain,
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

                final cardSizes = context.appCardSizes;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Bottom breathing room plus the device's own bottom
                  // system-UI inset, so the final row isn't obscured by
                  // a gesture bar / 3-button nav bar. 0 on Android
                  // TV/desktop.
                  padding: EdgeInsets.fromLTRB(
                    32,
                    8,
                    32,
                    48 + MediaQuery.paddingOf(context).bottom,
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: cardSizes.gridMaxWidth,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 24,
                    // Fixed absolute row height rather than
                    // childAspectRatio: AnimeCard's poster is
                    // width-driven (its own internal AspectRatio adapts
                    // to whatever column width the grid actually
                    // produces), but the text block beneath it is a
                    // fixed pixel height regardless of width. Deriving
                    // this extent from the widest possible column
                    // (gridMaxWidth) guarantees every narrower column —
                    // which always needs less height too, since its
                    // poster is proportionally shorter — still fits
                    // inside it without overflowing.
                    mainAxisExtent:
                        cardSizes.gridMaxWidth / cardSizes.posterAspectRatio +
                        AnimeCard.kTextBlockHeight,
                  ),
                  itemCount: results.length,
                  itemBuilder: (_, i) => AnimeCard(
                    // Keyed by anime id — a new search or filter apply reuses this
                    // GridView's Elements by position otherwise, which silently
                    // defeats `autofocus: i == 0` on the new top result.
                    key: ValueKey(results[i].id),
                    anime: results[i],
                    onSelect: widget.onSelectAnime,
                    autofocus: i == 0,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
