// lib/screens/watchlist_screen.dart
//
// Watchlist screen — translates WatchlistView.svelte into Flutter.
//
// Displays the authenticated user's CURRENT ("Watching") and PLANNING lists
// fetched from AniList via [AnilistApiService.getUserWatchlist].
// Tapping a card calls [onSelectAnime], routing through AppShell so the
// NavBar stays visible — identical to HomeScreen and SearchResultsScreen.

import 'package:flutter/material.dart';

import '../services/anilist_api.dart';
import '../theme/app_palette.dart';

// ════════════════════════════════════════════════════════════════════════════
//  WatchlistScreen
// ════════════════════════════════════════════════════════════════════════════

class WatchlistScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const WatchlistScreen({super.key, this.onSelectAnime});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _api = AnilistApiService();

  bool            _loading = true;
  String?         _error;
  List<MediaList> _lists   = [];
  String          _activeStatus = 'CURRENT'; // 'CURRENT' | 'PLANNING'

  @override
  void initState() {
    super.initState();
    _fetchWatchlist();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchWatchlist() async {
    setState(() { _loading = true; _error = null; });
    try {
      final lists = await _api.getUserWatchlist();
      if (mounted) setState(() { _lists = lists; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<MediaListEntry> get _activeEntries => _lists
      .where((l) => l.status == _activeStatus)
      .expand((l) => l.entries)
      .toList();

  int _columns(double width) {
    if (width < 600)  return 2;
    if (width < 900)  return 3;
    if (width < 1200) return 4;
    if (width < 1500) return 5;
    return 6;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header + tabs ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Row(
            children: [
              const Text(
                'My Library',
                style: TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              // Tab pill — mirrors the bg-surface/rounded-xl tab switcher
              // in WatchlistView.svelte.
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.border),
                ),
                child: Row(
                  children: [
                    _TabButton(
                      icon:   Icons.play_arrow_rounded,
                      label:  'Watching',
                      active: _activeStatus == 'CURRENT',
                      onTap:  () => setState(() => _activeStatus = 'CURRENT'),
                    ),
                    _TabButton(
                      icon:   Icons.calendar_today_outlined,
                      label:  'Planning',
                      active: _activeStatus == 'PLANNING',
                      onTap:  () => setState(() => _activeStatus = 'PLANNING'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Body ───────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const _LoadingPane()
              : _error != null
                  ? _ErrorPane(message: _error!, onRetry: _fetchWatchlist)
                  : _buildGrid(),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    final entries = _activeEntries;

    if (entries.isEmpty) {
      return _EmptyPane(
        message: _activeStatus == 'CURRENT'
            ? "You're not watching anything yet."
            : "Your planning list is empty.",
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _columns(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:  cols,
            crossAxisSpacing: 20,
            mainAxisSpacing:  24,
            // Slightly taller than the home grid to fit the extra info line.
            childAspectRatio: 0.52,
          ),
          itemCount: entries.length,
          itemBuilder: (_, i) => _WatchlistCard(
            entry:        entries[i],
            showProgress: _activeStatus == 'CURRENT',
            onTap: () => widget.onSelectAnime?.call(entries[i].media),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _TabButton
// ════════════════════════════════════════════════════════════════════════════

/// Watching / Planning tab pill button.
/// Active state mirrors `bg-primary text-white shadow-md` from Svelte.
class _TabButton extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     active;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppPalette.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [BoxShadow(
                  color: AppPalette.primary.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : AppPalette.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AppPalette.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _WatchlistCard
// ════════════════════════════════════════════════════════════════════════════

/// Individual media card — mirrors the `<button>` block in WatchlistView.svelte.
///
/// Shows:
///   • Poster with hover overlay ("Play EP N")
///   • Progress badge top-right (CURRENT tab only)
///   • Title (single line, ellipsis)
///   • Airing-soon chip  OR  episode count
class _WatchlistCard extends StatefulWidget {
  final MediaListEntry entry;
  final bool           showProgress;
  final VoidCallback?  onTap;

  const _WatchlistCard({
    required this.entry,
    required this.showProgress,
    this.onTap,
  });

  @override
  State<_WatchlistCard> createState() => _WatchlistCardState();
}

class _WatchlistCardState extends State<_WatchlistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final media    = widget.entry.media;
    final progress = widget.entry.progress;
    final nextEp   = media.nextAiringEpisode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Poster ──────────────────────────────────────────────────────────
        Expanded(
          child: MouseRegion(
            cursor:  SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit:  (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered
                        ? AppPalette.primary.withValues(alpha: 0.55)
                        : AppPalette.border,
                  ),
                  boxShadow: _hovered
                      ? [BoxShadow(
                          color:       AppPalette.primary.withValues(alpha: 0.18),
                          blurRadius:  24,
                          spreadRadius: 2,
                        )]
                      : const [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Cover image with zoom-on-hover
                      _PosterImage(
                        url:     media.coverImage?.display,
                        hovered: _hovered,
                      ),

                      // Progress badge — top-right, CURRENT tab only.
                      // Mirrors `{entry.progress} / {media.episodes || "?"}` in Svelte.
                      if (widget.showProgress)
                        Positioned(
                          top:   8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical:   4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.80),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Text(
                              '$progress / ${media.episodes ?? "?"}',
                              style: const TextStyle(
                                color:      Colors.white,
                                fontSize:   10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),

                      // Hover overlay — "Play EP N" pill, mirroring
                      // `Play EP {entry.progress + 1}` in WatchlistView.svelte.
                      _PlayOverlay(
                        visible: _hovered,
                        episode: progress + 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Title ────────────────────────────────────────────────────────────
        const SizedBox(height: 10),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color:      _hovered ? AppPalette.primary : AppPalette.textMain,
            fontSize:   13,
            fontWeight: FontWeight.w600,
            height:     1.35,
          ),
          child: Text(
            media.title.display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // ── Sub-line: airing chip or episode count ────────────────────────
        const SizedBox(height: 4),
        if (nextEp != null && nextEp.episode > 0)
          Text(
            'Ep ${nextEp.episode} airing soon',
            style: const TextStyle(
              color:      AppPalette.primary,
              fontSize:   11,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            '${media.episodes ?? "?"} episodes',
            style: const TextStyle(
              color:    AppPalette.textMuted,
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _PosterImage
// ════════════════════════════════════════════════════════════════════════════

/// Network image with a dark skeleton placeholder, fade-in, and scale-on-hover.
class _PosterImage extends StatelessWidget {
  final String? url;
  final bool    hovered;

  const _PosterImage({this.url, required this.hovered});

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
      scale:    hovered ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve:    Curves.easeOut,
      child: Image.network(
        url!,
        fit:    BoxFit.cover,
        width:  double.infinity,
        height: double.infinity,
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppPalette.surface),
              AnimatedOpacity(
                opacity:  frame != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                curve:    Curves.easeOut,
                child:    child,
              ),
            ],
          );
        },
        errorBuilder: (_, __, ___) => const ColoredBox(
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
//  _PlayOverlay
// ════════════════════════════════════════════════════════════════════════════

/// Hover overlay that shows a "Play EP N" pill — mirrors the
/// `opacity-0 group-hover:opacity-100 … Play EP {entry.progress + 1}` block
/// in WatchlistView.svelte.
class _PlayOverlay extends StatelessWidget {
  final bool visible;
  final int  episode;

  const _PlayOverlay({required this.visible, required this.episode});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity:  visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.52),
          child: Center(
            child: AnimatedSlide(
              offset:   visible ? Offset.zero : const Offset(0, 0.12),
              duration: const Duration(milliseconds: 250),
              curve:    Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical:   9,
                ),
                decoration: BoxDecoration(
                  color:         AppPalette.primary,
                  borderRadius:  BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color:      AppPalette.primary.withValues(alpha: 0.55),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Text(
                  'Play EP $episode',
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  State panes
// ════════════════════════════════════════════════════════════════════════════

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
      strokeWidth: 2.5,
    ),
  );
}

class _EmptyPane extends StatelessWidget {
  final String message;
  const _EmptyPane({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(32, 0, 32, 32),
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppPalette.border,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.video_library_outlined,
              color: AppPalette.textMuted,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: AppPalette.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Find something new to watch!',
              style: TextStyle(color: AppPalette.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String       message;
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
            'Could not load watchlist',
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
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppPalette.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon:  const Icon(Icons.refresh_rounded),
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
