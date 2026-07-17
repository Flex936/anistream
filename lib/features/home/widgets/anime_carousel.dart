import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/anilist_query_service.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/widgets/anime_card.dart';

class AnimeCarousel extends StatefulWidget {
  final String title;
  final Future<List<Anime>> future;
  final ValueChanged<Anime>? onSelectAnime;
  final VoidCallback onRetry;
  final bool autofocusFirst;
  final bool uiPerformanceMode;

  const AnimeCarousel({
    super.key,
    required this.title,
    required this.future,
    this.onSelectAnime,
    required this.onRetry,
    this.autofocusFirst = false,
    this.uiPerformanceMode = false,
  });

  @override
  State<AnimeCarousel> createState() => _AnimeCarouselState();
}

class _AnimeCarouselState extends State<AnimeCarousel> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkScrollLimits);
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
    final canRight =
        _scrollController.offset < _scrollController.position.maxScrollExtent;

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double directionMultiplier) {
    if (!_scrollController.hasClients) return;

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
    final isMobile = MediaQuery.sizeOf(context).width < 600;
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppPalette.primary,
                    ),
                    strokeWidth: 2.5,
                  ),
                );
              }

              if (snapshot.hasError) {
                final err = snapshot.error;
                final msg = err is AnilistException
                    ? err.message
                    : 'Could not load anime.';
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: AppPalette.textMuted,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        msg,
                        style: const TextStyle(
                          color: AppPalette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: widget.onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try Again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppPalette.primary,
                          side: const BorderSide(color: AppPalette.primary),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'No anime found.',
                    style: TextStyle(color: AppPalette.textMuted),
                  ),
                );
              }

              return MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: Stack(
                  children: [
                    ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 20),
                        itemBuilder: (context, i) {
                          return SizedBox(
                            width: 170,
                            child: AnimeCard(
                              anime: items[i],
                              onSelect: widget.onSelectAnime,
                              autofocus: widget.autofocusFirst && i == 0,
                            ),
                          );
                        },
                      ),
                    ),

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
                            AppPalette.base.withValues(alpha: 0.0),
                          ],
                          uiPerformanceMode: widget.uiPerformanceMode,
                          onTap: () => _scroll(-1.0),
                        ),
                      ),

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
                            AppPalette.base.withValues(alpha: 0.9),
                          ],
                          uiPerformanceMode: widget.uiPerformanceMode,
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

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final Alignment alignment;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final bool uiPerformanceMode;

  const _NavArrow({
    required this.icon,
    required this.alignment,
    required this.gradientColors,
    required this.onTap,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // The core arrow button visual
    final arrowContent = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        // Increase opacity if blur is disabled to maintain contrast
        color: AppPalette.black.withValues(
          alpha: uiPerformanceMode ? 0.8 : 0.4,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
      ),
      child: Icon(icon, color: AppPalette.white, size: 28),
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: uiPerformanceMode
              ? arrowContent // Return without blur
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: arrowContent, // Return with frosted glass
                ),
        ),
      ),
    );
  }
}
