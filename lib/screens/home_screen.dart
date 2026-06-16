// lib/screens/home_screen.dart
//
// Discovery / Home screen for AniStream.
// Translates the Wails/Svelte DiscoveryView + AnimeCard into Flutter widgets.
//
// Design tokens are sourced 1-to-1 from frontend/style.css @theme variables.
// Status colours are sourced from frontend/lib/utils/statusColor.ts.
//
// Required import in the file that calls runApp / MaterialApp:
//   import 'package:flutter/material.dart';
//   import 'home_screen.dart';

import 'dart:ui';

import 'package:anistream/screens/anime_details_screen.dart';
import 'package:flutter/material.dart';

import '../services/anilist_api.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens
//  Maps every CSS variable in style.css to a Dart constant.
// ════════════════════════════════════════════════════════════════════════════

abstract final class AppPalette {
  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const Color base = Color(0xFF0A0A0C); // --color-base
  static const Color surface = Color(0xFF14151A); // --color-surface
  static const Color overlay = Color(0xFF1C1D24); // --color-overlay
  static const Color border = Color(0xFF272A35); // --color-border

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6366F1); // --color-primary
  static const Color primaryHover = Color(0xFF4F46E5); // --color-primary-hover
  static const Color accent = Color(0xFFFBBF24); // --color-accent

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textMain = Color(0xFFF1F5F9); // --color-main
  static const Color textMuted = Color(0xFF94A3B8); // --color-muted

  // ── Status badges — from statusColor.ts ──────────────────────────────────
  static const Color statusReleasing = Color(0xFF4ADE80); // text-green-400
  static const Color statusFinished = Color(0xFF38BDF8); // text-sky-400
  static const Color statusCancelled = Color(0xFFF87171); // text-red-400
  static const Color statusHiatus = Color(0xFFFB923C); // text-orange-400
  static const Color statusDefault = Color(0xFF94A3B8); // text-muted
}

// ════════════════════════════════════════════════════════════════════════════
//  Private helpers (replicate statusColor.ts logic)
// ════════════════════════════════════════════════════════════════════════════

/// Mirrors [getCardStatusColor] from statusColor.ts.
Color _statusColor(String? status) => switch (status) {
  'RELEASING' => AppPalette.statusReleasing,
  'FINISHED' => AppPalette.statusFinished,
  'CANCELLED' => AppPalette.statusCancelled,
  'HIATUS' => AppPalette.statusHiatus,
  _ => AppPalette.statusDefault,
};

/// Mirrors [formatStatus] from statusColor.ts.
String _formatStatus(String? status) =>
    (status ?? 'UNKNOWN').replaceAll('_', ' ');

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

// ════════════════════════════════════════════════════════════════════════════
//  AnimeCard  (replaces AnimeCard.svelte)
// ════════════════════════════════════════════════════════════════════════════

class AnimeCard extends StatefulWidget {
  final Anime anime;
  const AnimeCard({super.key, required this.anime});

  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final anime = widget.anime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Poster ──────────────────────────────────────────────────────────
        Expanded(
          child: MouseRegion(
            // SystemMouseCursors.click gives the hand cursor on desktop —
            // the Flutter equivalent of Svelte's cursor-pointer class.
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnimeDetailsScreen(anime: anime),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  // Border transitions from border → primary/55 on hover,
                  // mirroring group-hover:border-primary/50 in AnimeCard.svelte.
                  border: Border.all(
                    color: _hovered
                        ? AppPalette.primary.withValues(alpha: 0.55)
                        : AppPalette.border,
                  ),
                  // Glow shadow on hover, matching the primary ring effect.
                  boxShadow: _hovered
                      ? [
                          BoxShadow(
                            color: AppPalette.primary.withValues(alpha: 0.18),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ]
                      : const [],
                ),
                // ClipRRect constrains the scale animation and the hover
                // overlay to the card's rounded rect — no overflow bleed.
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Layer 1 — cover image with fade-in + hover zoom
                      _CoverImage(
                        url: anime.coverImage?.extraLarge,
                        hovered: _hovered,
                      ),

                      // Layer 2 — bottom gradient scrim + score badge
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _PosterGradient(score: anime.averageScore),
                      ),

                      // Layer 3 — top-left status badge (glassmorphic)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _StatusBadge(
                          label: _formatStatus(anime.status),
                          color: _statusColor(anime.status),
                        ),
                      ),

                      // Layer 4 — translucent play overlay (hover only)
                      _HoverOverlay(visible: _hovered),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Title + episode count below the poster ───────────────────────────
        const SizedBox(height: 10),
        // AnimatedDefaultTextStyle smoothly transitions the title colour on
        // hover, matching group-hover:text-primary transition-colors in Svelte.
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: _hovered ? AppPalette.primary : AppPalette.textMain,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
          child: Text(
            anime.title.display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${anime.episodes ?? '?'} Episodes',
          style: const TextStyle(color: AppPalette.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _CoverImage
// ════════════════════════════════════════════════════════════════════════════

/// Network poster image with two features:
///
/// 1. **Fade-in on load** — [Image.network]'s [frameBuilder] replaces the
///    skeleton placeholder with the decoded image via [AnimatedOpacity],
///    mirroring `transition-opacity duration-500` on the <img> in Svelte.
///
/// 2. **Subtle zoom on hover** — [AnimatedScale] scales 1.0 → 1.05 inside the
///    [ClipRRect] in the parent card, so overflow is never visible.
class _CoverImage extends StatelessWidget {
  final String? url;
  final bool hovered;

  const _CoverImage({this.url, required this.hovered});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(
        color: AppPalette.surface,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: AppPalette.textMuted,
            size: 36,
          ),
        ),
      );
    }

    return AnimatedScale(
      // hover zoom — mirrors group-hover scale on the image
      scale: hovered ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // frameBuilder is called each time a new image frame is available.
        // When frame == null the image is still decoding; we show the dark
        // surface skeleton and cross-fade in the real image once ready.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          // Cached / synchronous images don't need the animation.
          if (wasSynchronouslyLoaded) return child;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Dark surface skeleton — mirrors `animate-pulse bg-surface`
              const ColoredBox(color: AppPalette.surface),
              // Cross-fade in the real image on the first decoded frame
              AnimatedOpacity(
                opacity: frame != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                child: child,
              ),
            ],
          );
        },
        errorBuilder: (_, _, _) => const ColoredBox(
          color: AppPalette.surface,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppPalette.textMuted,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _PosterGradient
// ════════════════════════════════════════════════════════════════════════════

/// Recreates the `.player-scrim` gradient from style.css at the bottom of
/// each poster, and optionally shows the AniList score with a star icon.
class _PosterGradient extends StatelessWidget {
  final int? score;
  const _PosterGradient({this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 48, 10, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Color(0xB3000000), // 70 % black — matches 0.4 stop in .player-scrim
            Color(0xE6000000), // 90 % black — matches 0.9 stop in .player-scrim
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: score != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: AppPalette.accent,
                  size: 14,
                ),
                const SizedBox(width: 3),
                Text(
                  (score! / 10).toStringAsFixed(1),
                  style: const TextStyle(
                    color: AppPalette.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _StatusBadge
// ════════════════════════════════════════════════════════════════════════════

/// Top-left status badge with a real glassmorphic backdrop blur.
///
/// [ClipRRect] is mandatory — [BackdropFilter] only respects the rounded
/// corner if an ancestor clips the canvas to that shape.
///
/// Mirrors the `bg-black/70 backdrop-blur-sm` + coloured border in AnimeCard.svelte.
class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.40)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _HoverOverlay
// ════════════════════════════════════════════════════════════════════════════

/// Full-card translucent overlay with a centred play button, visible on hover.
///
/// [IgnorePointer] ensures all hit-tests fall through to the [GestureDetector]
/// that wraps the card — the overlay is purely decorative.
///
/// Mirrors the `absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100`
/// div in AnimeCard.svelte, including the `translate-y-4 → translate-y-0`
/// slide-up animation on the play button.
class _HoverOverlay extends StatelessWidget {
  final bool visible;
  const _HoverOverlay({required this.visible});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        // ColoredBox fills StackFit.expand from the parent Stack.
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.42),
          child: Center(
            child: AnimatedSlide(
              // Slide up from +12 % when appearing — mirrors translate-y-4
              offset: visible ? Offset.zero : const Offset(0.0, 0.12),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppPalette.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.primary.withValues(alpha: 0.55),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
