import 'dart:ui';
import 'package:flutter/material.dart';

// ── Updated import to match your new service name ──
import '../services/anilist_query_service.dart';
import '../theme/app_palette.dart';
import '../widgets/anime_card.dart';

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
  // ── Updated to AnilistQueryService ──
  late final AnilistQueryService _api;
  Future<List<Anime>>? _searchFuture;

  // ── Active Filters ──
  int _minScore = 0;
  String _selectedStatus = 'ANY';
  // We use the current year + 1 to represent "ANY" year
  late double _selectedYear; 

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year.toDouble() + 1; // Default to "ANY"
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
      setState(() => _searchFuture = null);
      return;
    }
    
    setState(() {
      // ── Filters are now fully wired up to the API! ──
      _searchFuture = _api.searchAnime(
        widget.query,
        minScore: _minScore > 0 ? _minScore : null,
        status: _selectedStatus == 'ANY' ? null : _selectedStatus,
        // If the slider is at the max (current year + 1), we pass null to ignore the year filter
        year: _selectedYear > DateTime.now().year ? null : _selectedYear.toInt(),
      );
    });
  }

  void _openFilterDrawer() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      // Mobile: Slide up Frosted Bottom Sheet
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _buildFilterPanel(),
      );
    } else {
      // Desktop: Slide in Frosted Side Panel from the right
      showGeneralDialog(
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
              child: _buildFilterPanel(),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      );
    }
  }

  Widget _buildFilterPanel() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final currentYear = DateTime.now().year;
        final isAnyYear = _selectedYear > currentYear;

        return ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Material(
              color: AppPalette.base.withValues(alpha: 0.75),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Filters', style: TextStyle(color: AppPalette.textMain, fontSize: 24, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: AppPalette.textMuted), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // ── Status Filter ──
                    const Text('Status', style: TextStyle(color: AppPalette.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: ['ANY', 'RELEASING', 'FINISHED'].map((status) {
                        final isSelected = _selectedStatus == status;
                        return ChoiceChip(
                          label: Text(status),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) setModalState(() => _selectedStatus = status);
                          },
                          backgroundColor: AppPalette.surface,
                          selectedColor: AppPalette.primary.withValues(alpha: 0.2),
                          labelStyle: TextStyle(color: isSelected ? AppPalette.primary : AppPalette.textMain, fontSize: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: isSelected ? AppPalette.primary : AppPalette.border),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 32),

                    // ── Minimum Score Filter ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Minimum Score', style: TextStyle(color: AppPalette.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(_minScore == 0 ? 'Any' : '$_minScore', style: const TextStyle(color: AppPalette.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(activeTrackColor: AppPalette.primary, thumbColor: AppPalette.primary, inactiveTrackColor: AppPalette.border),
                      child: Slider(
                        value: _minScore.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: (val) => setModalState(() => _minScore = val.toInt()),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Year Filter ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Release Year', style: TextStyle(color: AppPalette.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(isAnyYear ? 'Any' : '${_selectedYear.toInt()}', style: const TextStyle(color: AppPalette.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(activeTrackColor: AppPalette.primary, thumbColor: AppPalette.primary, inactiveTrackColor: AppPalette.border),
                      child: Slider(
                        value: _selectedYear,
                        min: 1980,
                        max: currentYear.toDouble() + 1,
                        divisions: (currentYear + 1) - 1980,
                        onChanged: (val) => setModalState(() => _selectedYear = val),
                      ),
                    ),

                    const Spacer(),
                    
                    // ── Apply Button ──
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppPalette.primary, foregroundColor: AppPalette.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () {
                          Navigator.pop(context);
                          // Save filters to main state and search
                          setState(() {}); 
                          _executeSearch();
                        },
                        child: const Text('Apply Filters', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      }
    );
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
    if (widget.query.trim().isEmpty) {
      return const SizedBox.shrink(); // Show nothing if no text
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 96), // Push below NavBar

          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            child: Row(
              children: [
                Text(
                  'Results for "${widget.query}"',
                  style: const TextStyle(color: AppPalette.textMain, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4),
                ),
                const SizedBox(width: 16),
                
                // ── Search Loader ──
                if (_searchFuture != null)
                  FutureBuilder(
                    future: _searchFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(AppPalette.primary)));
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                const Spacer(),
                
                // ── The Filters Button ──
                OutlinedButton.icon(
                  onPressed: _openFilterDrawer,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.textMain,
                    side: const BorderSide(color: AppPalette.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  return SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppPalette.primary))));
                }
                if (snapshot.hasError) {
                  return SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: Center(child: Text('Search failed: ${snapshot.error}', style: const TextStyle(color: AppPalette.statusCancelled))));
                }

                final results = snapshot.data ?? [];
                if (results.isEmpty) {
                  return SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: const Center(child: Text('No anime found.', style: TextStyle(color: AppPalette.textMuted, fontSize: 15))));
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = _animeGridColumns(constraints.maxWidth);
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