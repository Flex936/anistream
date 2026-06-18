import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../widgets/anime_card.dart';
import '../services/anilist_query_service.dart';

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
    _loadTrending();
    _loadSeasonPopular();
    _loadAllTimePopular();
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
            // ── FIXED: Increased spacer to 96 to safely clear the glass NavBar ──
            const SizedBox(height: 96),
            
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
//  Anime Carousel (Horizontal List with Desktop Navigation)
// ════════════════════════════════════════════════════════════════════════════

class _AnimeCarousel extends StatefulWidget {
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
  State<_AnimeCarousel> createState() => _AnimeCarouselState();
}

class _AnimeCarouselState extends State<_AnimeCarousel> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkScrollLimits);
    // Give it a short delay to measure constraints after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScrollLimits());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_checkScrollLimits);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkScrollLimits() {
    if (!_scrollController.hasClients) return;
    
    final canLeft = _scrollController.offset > 0;
    final canRight = _scrollController.offset < _scrollController.position.maxScrollExtent;

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double directionMultiplier) {
    if (!_scrollController.hasClients) return;
    
    // Scroll by roughly 3 cards at a time (170px + 20px padding * 3)
    final double scrollAmount = 570.0 * directionMultiplier;
    final double targetPosition = (_scrollController.offset + scrollAmount)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      targetPosition,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── FIXED: Mobile Responsiveness Check ──
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hPad = isMobile ? 16.0 : 32.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 16),
          child: Text(
            widget.title,
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
            future: widget.future,
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
                return Center(
                  child: OutlinedButton.icon(
                    onPressed: widget.onRetry,
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

              return MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: Stack(
                  children: [
                    // ── FIXED: Allow mouse dragging on desktop ──
                    ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                      ),
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 20),
                        itemBuilder: (context, i) {
                          return SizedBox(
                            width: 170,
                            child: AnimeCard(
                              anime: items[i],
                              onSelect: widget.onSelectAnime,
                            ),
                          );
                        },
                      ),
                    ),

                    // ── LEFT NAVIGATION ARROW (Desktop only) ──
                    if (!isMobile && _isHovered && _canScrollLeft)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: _NavArrow(
                          icon: Icons.chevron_left_rounded,
                          alignment: Alignment.centerLeft,
                          gradientColors: [
                            AppPalette.base.withValues(alpha: 0.9),
                            AppPalette.base.withValues(alpha: 0.0)
                          ],
                          onTap: () => _scroll(-1.0),
                        ),
                      ),

                    // ── RIGHT NAVIGATION ARROW (Desktop only) ──
                    if (!isMobile && _isHovered && _canScrollRight)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: _NavArrow(
                          icon: Icons.chevron_right_rounded,
                          alignment: Alignment.centerRight,
                          gradientColors: [
                            AppPalette.base.withValues(alpha: 0.0),
                            AppPalette.base.withValues(alpha: 0.9)
                          ],
                          onTap: () => _scroll(1.0),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _NavArrow (Netflix-style scroll button)
// ════════════════════════════════════════════════════════════════════════════

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final Alignment alignment;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _NavArrow({
    required this.icon,
    required this.alignment,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppPalette.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
              ),
              child: Icon(icon, color: AppPalette.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}