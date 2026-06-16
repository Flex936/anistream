// Anime details + episode picker for AniStream's desktop layout.
// Translates TheaterView.svelte + AnimeDetailsSidebar.svelte + TorrentList.svelte
// into a single Flutter screen using a premium split-pane Row.
//
// Architecture note:
//   AppPalette is imported from home_screen.dart for now.
//   TODO(refactor): extract AppPalette into lib/theme/palette.dart so screens
//   never cross-import each other.

import 'package:flutter/material.dart';
import 'package:anistream/main.dart';

import '../services/anilist_api.dart';
import '../services/torrent_scraper.dart';
import 'home_screen.dart';
import 'theater_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
//  File-private helpers
// ════════════════════════════════════════════════════════════════════════════

/// Strips HTML from AniList's description, converting <br> tags to newlines.
/// We avoid adding flutter_html as a dependency to keep the app lean.
String _stripHtml(String? html) {
  if (html == null || html.isEmpty) return 'No synopsis available.';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Status → colour, mirroring [_statusColor] in home_screen.dart.
Color _statusColor(String? s) => switch (s) {
  'RELEASING' => AppPalette.statusReleasing,
  'FINISHED' => AppPalette.statusFinished,
  'CANCELLED' => AppPalette.statusCancelled,
  'HIATUS' => AppPalette.statusHiatus,
  _ => AppPalette.statusDefault,
};

/// Status → display string, mirroring [formatStatus] in statusColor.ts.
String _formatStatus(String? s) => (s ?? 'UNKNOWN').replaceAll('_', ' ');

/// Seeder count → health colour (green → amber → red).
Color _seederColor(int n) {
  if (n > 100) return AppPalette.statusReleasing; // healthy
  if (n > 20) return AppPalette.accent; // moderate
  return AppPalette.statusCancelled; // dead
}

// ════════════════════════════════════════════════════════════════════════════
//  AnimeDetailsScreen
// ════════════════════════════════════════════════════════════════════════════

/// Desktop split-pane detail screen.
///
/// Left sidebar  (flex 3) — cover art + metadata + synopsis.
/// Right panel   (flex 7) — episode accordion with torrent picker.
class AnimeDetailsScreen extends StatefulWidget {
  final Anime anime;
  const AnimeDetailsScreen({super.key, required this.anime});

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> {
  final TorrentScraperService _scraper = TorrentScraperService();

  /// Episode number currently open in the accordion (-1 = none).
  int _expandedEpisode = -1;

  /// Future cache — [putIfAbsent] guarantees each episode is fetched once,
  /// even when the user collapses and re-expands the same tile.
  final Map<int, Future<List<Torrent>>> _torrentFutures = {};

  /// Fallback episode count when AniList omits the field.
  int get _episodeCount => widget.anime.episodes ?? 12;

  /// Returns a cached future for [ep], starting a new fetch on first call.
  Future<List<Torrent>> _futureFor(int ep) => _torrentFutures.putIfAbsent(
    ep,
    () => _scraper.fetchTorrents(widget.anime.title.display, ep),
  );

  void _toggleEpisode(int ep) => setState(() {
    _expandedEpisode = _expandedEpisode == ep ? -1 : ep;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.base,
      body: Column(
        children: [
          // ── Top navigation bar ──────────────────────────────────────────
          _NavBar(anime: widget.anime),

          // ── Main split-pane ─────────────────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left sidebar — flex 3
                Expanded(flex: 3, child: _LeftSidebar(anime: widget.anime)),

                // 1 px vertical divider
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppPalette.border,
                ),

                // Right episode panel — flex 7
                Expanded(
                  flex: 7,
                  child: _EpisodePanel(
                    episodeCount: _episodeCount,
                    expandedEpisode: _expandedEpisode,
                    futureFor: _futureFor,
                    onToggle: _toggleEpisode,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _NavBar
//  Mirrors the "Back to Discovery" button in TheaterView.svelte.
// ════════════════════════════════════════════════════════════════════════════

class _NavBar extends StatefulWidget {
  final Anime anime;
  const _NavBar({required this.anime});

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> {
  bool _backHovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(bottom: BorderSide(color: AppPalette.border)),
      ),
      child: Row(
        children: [
          // Back button — mirrors <ArrowLeft> group-hover in TheaterView.svelte
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _backHovered = true),
            onExit: (_) => setState(() => _backHovered = false),
            child: GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _backHovered ? AppPalette.border : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSlide(
                      offset: _backHovered
                          ? const Offset(-0.15, 0)
                          : Offset.zero,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 16,
                        color: _backHovered
                            ? AppPalette.textMain
                            : AppPalette.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Back to Discovery',
                      style: TextStyle(
                        color: _backHovered
                            ? AppPalette.textMain
                            : AppPalette.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Separator
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: AppPalette.border,
          ),

          // Truncated anime title for breadcrumb context
          Expanded(
            child: Text(
              widget.anime.title.display,
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _LeftSidebar
//  Mirrors AnimeDetailsSidebar.svelte — cover image + meta + synopsis.
// ════════════════════════════════════════════════════════════════════════════

class _LeftSidebar extends StatelessWidget {
  final Anime anime;
  const _LeftSidebar({required this.anime});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppPalette.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover image ─────────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: _NetworkImage(
                  // Prefer extraLarge cover; fall back to banner if absent.
                  url: anime.coverImage?.extraLarge ?? anime.bannerImage,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Romaji title ────────────────────────────────────────────────
            Text(
              anime.title.romaji ?? anime.title.english ?? 'Unknown Title',
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),

            // English title (only when it differs from romaji)
            if (anime.title.english != null &&
                anime.title.english != anime.title.romaji) ...[
              const SizedBox(height: 4),
              Text(
                anime.title.english!,
                style: const TextStyle(
                  color: AppPalette.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Metadata chips ──────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  label: _formatStatus(anime.status),
                  color: _statusColor(anime.status),
                ),
                if (anime.episodes != null)
                  _MetaChip(
                    label: '${anime.episodes} ep',
                    color: AppPalette.textMuted,
                  ),
                if (anime.averageScore != null)
                  _MetaChip(
                    label: '★ ${(anime.averageScore! / 10).toStringAsFixed(1)}',
                    color: AppPalette.accent,
                  ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(color: AppPalette.border),
            const SizedBox(height: 16),

            // ── Synopsis ────────────────────────────────────────────────────
            const Text(
              'SYNOPSIS',
              style: TextStyle(
                color: AppPalette.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _stripHtml(anime.description),
              style: const TextStyle(
                color: AppPalette.textMuted,
                fontSize: 13,
                height: 1.75,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _EpisodePanel
//  Stateless host for the ListView — all expansion state lives in the parent.
// ════════════════════════════════════════════════════════════════════════════

class _EpisodePanel extends StatelessWidget {
  final int episodeCount;
  final int expandedEpisode;

  /// Retrieves (or lazily creates) the [Future] for a given episode number.
  final Future<List<Torrent>> Function(int ep) futureFor;
  final ValueChanged<int> onToggle;

  const _EpisodePanel({
    required this.episodeCount,
    required this.expandedEpisode,
    required this.futureFor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Panel header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          child: Row(
            children: [
              const Text(
                'Episodes',
                style: TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              // Episode count pill — mirrors the "X / Y Aired" badge in EpisodeList.svelte
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppPalette.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '$episodeCount',
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppPalette.border),

        // ── Episode accordion ───────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: episodeCount,
            itemBuilder: (context, index) {
              final ep = index + 1;
              final isExpanded = expandedEpisode == ep;
              return _EpisodeTile(
                // ValueKey keeps State alive while the tile stays in the tree,
                // preventing hover/expansion state loss on scroll.
                key: ValueKey(ep),
                episodeNumber: ep,
                isExpanded: isExpanded,
                // Only pass the future when the tile is open — putIfAbsent
                // inside futureFor() ensures a single network call per ep.
                torrentFuture: isExpanded ? futureFor(ep) : null,
                onToggle: () => onToggle(ep),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _EpisodeTile
//  Manages hover state locally; expansion state is owned by the screen.
// ════════════════════════════════════════════════════════════════════════════

class _EpisodeTile extends StatefulWidget {
  final int episodeNumber;
  final bool isExpanded;

  /// Non-null only when [isExpanded] is true; guards the FutureBuilder.
  final Future<List<Torrent>>? torrentFuture;
  final VoidCallback onToggle;

  const _EpisodeTile({
    super.key,
    required this.episodeNumber,
    required this.isExpanded,
    this.torrentFuture,
    required this.onToggle,
  });

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header row ──────────────────────────────────────────────────────
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onToggle,
            // opaque ensures the full row registers taps, not just child widgets
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
              decoration: BoxDecoration(
                color: widget.isExpanded
                    ? AppPalette.primary.withValues(alpha: 0.06)
                    : _hovered
                    ? Colors.white.withValues(alpha: 0.025)
                    : Colors.transparent,
                // Left accent bar — classic "selected row" pattern from VS Code / Svelte sidebar
                border: Border(
                  left: BorderSide(
                    color: widget.isExpanded
                        ? AppPalette.primary
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Bold episode number in monospace — matches the large "01" in EpisodeList.svelte
                  SizedBox(
                    width: 34,
                    child: Text(
                      widget.episodeNumber.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: widget.isExpanded
                            ? AppPalette.primary
                            : AppPalette.textMuted.withValues(alpha: 0.35),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Episode label
                  Expanded(
                    child: Text(
                      'Episode ${widget.episodeNumber}',
                      style: TextStyle(
                        color: widget.isExpanded
                            ? AppPalette.textMain
                            : AppPalette.textMuted,
                        fontSize: 14,
                        fontWeight: widget.isExpanded
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),

                  // Animated chevron — rotates 180° when expanded
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: widget.isExpanded
                          ? AppPalette.primary
                          : AppPalette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Animated torrent list ───────────────────────────────────────────
        // AnimatedSize smoothly transitions height when children appear/disappear,
        // giving a native accordion feel without TickerProvider boilerplate.
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: widget.isExpanded
              ? _buildTorrentContent()
              : const SizedBox.shrink(),
        ),

        // ── Row divider ─────────────────────────────────────────────────────
        const Divider(height: 1, thickness: 1, color: AppPalette.border),
      ],
    );
  }

  Widget _buildTorrentContent() {
    final future = widget.torrentFuture;
    // Guard: should never be null when isExpanded, but defensive beats crashing.
    if (future == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: FutureBuilder<List<Torrent>>(
        future: future,
        builder: (context, snapshot) {
          // ── Loading ──────────────────────────────────────────────────────
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppPalette.primary,
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Searching for releases…',
                    style: TextStyle(color: AppPalette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          // ── Error ────────────────────────────────────────────────────────
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppPalette.statusCancelled,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Failed to load releases: ${snapshot.error}',
                      style: const TextStyle(
                        color: AppPalette.statusCancelled,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // ── Empty ────────────────────────────────────────────────────────
          final torrents = snapshot.data ?? [];
          if (torrents.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No releases found for this episode.',
                style: TextStyle(color: AppPalette.textMuted, fontSize: 13),
              ),
            );
          }

          // ── Torrent list ─────────────────────────────────────────────────
          // Collection for-loop avoids a separate List.generate call and lets
          // us interleave spacing/recommended badge inline.
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              for (int i = 0; i < torrents.length; i++) ...[
                _TorrentTile(
                  torrent: torrents[i],
                  isRecommended: i == 0,
                  onStream: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TheaterScreen(
                          episode: widget.episodeNumber,
                          torrent: torrents[i],
                        ),
                      ),
                    );
                  },
                ),
                if (i < torrents.length - 1) const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _TorrentTile
//  Mirrors a single row in TorrentList.svelte — group badge + meta + play btn.
// ════════════════════════════════════════════════════════════════════════════

class _TorrentTile extends StatefulWidget {
  final Torrent torrent;

  /// True for the first (highest-score) result, mirrors "Recommended" label
  /// in TorrentList.svelte when [torrentSearch] is empty.
  final bool isRecommended;
  final VoidCallback onStream;

  const _TorrentTile({
    required this.torrent,
    this.isRecommended = false,
    required this.onStream,
  });

  @override
  State<_TorrentTile> createState() => _TorrentTileState();
}

class _TorrentTileState extends State<_TorrentTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.torrent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Recommended label (first result only) ──────────────────────────
        if (widget.isRecommended) ...[
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: AppPalette.accent,
                size: 11,
              ),
              const SizedBox(width: 4),
              const Text(
                'RECOMMENDED',
                style: TextStyle(
                  color: AppPalette.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],

        // ── Tile body ──────────────────────────────────────────────────────
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              // Recommended tile has a faint primary tint at rest
              color: _hovered
                  ? AppPalette.primary.withValues(alpha: 0.09)
                  : widget.isRecommended
                  ? AppPalette.primary.withValues(alpha: 0.06)
                  : AppPalette.overlay,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? AppPalette.primary.withValues(alpha: 0.40)
                    : widget.isRecommended
                    ? AppPalette.primary.withValues(alpha: 0.22)
                    : AppPalette.border,
              ),
            ),
            child: Row(
              children: [
                // ── Left: release group + metadata ──────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Release group chip — monospace to match bracket formatting
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppPalette.border),
                        ),
                        child: Text(
                          t.releaseGroup,
                          style: const TextStyle(
                            color: AppPalette.textMain,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Metadata row: resolution pill · size · seeder count
                      Row(
                        children: [
                          _Pill(t.resolution),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.save_rounded,
                            size: 11,
                            color: AppPalette.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            t.size,
                            style: const TextStyle(
                              color: AppPalette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // ▲ seeder count with health colour (mirrors TorrentList.svelte)
                          Text(
                            '▲ ${t.seeders}',
                            style: TextStyle(
                              color: _seederColor(t.seeders),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ── Right: stream button ─────────────────────────────────────
                // Mirrors the round play icon in TorrentList.svelte:
                //   bg-transparent text-muted/30 → group-hover:bg-primary/10
                //   group-hover:text-primary     → hover:!bg-primary hover:!text-white
                GestureDetector(
                  onTap: widget.onStream,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hovered
                          ? AppPalette.primary
                          : AppPalette.primary.withValues(alpha: 0.10),
                      boxShadow: _hovered
                          ? [
                              BoxShadow(
                                color: AppPalette.primary.withValues(
                                  alpha: 0.40,
                                ),
                                blurRadius: 14,
                              ),
                            ]
                          : const [],
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 20,
                      color: _hovered ? Colors.white : AppPalette.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Shared micro-widgets
// ════════════════════════════════════════════════════════════════════════════

/// Small network image with a dark skeleton placeholder and fade-in on load.
/// Reuses the same [frameBuilder] pattern established in home_screen.dart.
class _NetworkImage extends StatelessWidget {
  final String? url;
  const _NetworkImage({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(
        color: AppPalette.overlay,
        child: Center(
          child: Icon(
            Icons.movie_creation_outlined,
            color: AppPalette.textMuted,
            size: 48,
          ),
        ),
      );
    }

    return Image.network(
      url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppPalette.overlay),
            AnimatedOpacity(
              opacity: frame != null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
      errorBuilder: (_, _, _) => const ColoredBox(
        color: AppPalette.overlay,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: AppPalette.textMuted,
            size: 48,
          ),
        ),
      ),
    );
  }
}

/// Rounded resolution/category label (e.g. "1080p").
/// Styled with the primary colour so it stands out against the dark tile.
class _Pill extends StatelessWidget {
  final String label;
  const _Pill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppPalette.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppPalette.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Rounded metadata badge used in the sidebar for status / episodes / score.
/// Mirrors the [getSidebarBadgeStyle] tokens in statusColor.ts.
class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
