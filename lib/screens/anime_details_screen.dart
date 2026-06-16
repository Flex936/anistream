import 'package:flutter/material.dart';

import '../services/anilist_api.dart';
import '../services/torrent_scraper.dart';
import '../theme/app_palette.dart';
import '../widgets/episode_tile.dart';
import '../widgets/network_image.dart';

// ════════════════════════════════════════════════════════════════════════════
//  File-private helpers
// ════════════════════════════════════════════════════════════════════════════

String _stripHtml(String? html) {
  if (html == null || html.isEmpty) return 'No synopsis available.';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

Color _statusColor(String? s) => switch (s) {
  'RELEASING' => AppPalette.statusReleasing,
  'FINISHED' => AppPalette.statusFinished,
  'CANCELLED' => AppPalette.statusCancelled,
  'HIATUS' => AppPalette.statusHiatus,
  _ => AppPalette.statusDefault,
};

String _formatStatus(String? s) => (s ?? 'UNKNOWN').replaceAll('_', ' ');

// ════════════════════════════════════════════════════════════════════════════
//  AnimeDetailsScreen
// ════════════════════════════════════════════════════════════════════════════

class AnimeDetailsScreen extends StatefulWidget {
  final Anime anime;
  const AnimeDetailsScreen({super.key, required this.anime});

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> {
  final TorrentScraperService _scraper = TorrentScraperService();
  int _expandedEpisode = -1;
  final Map<int, Future<List<Torrent>>> _torrentFutures = {};

  int get _episodeCount {
    if (widget.anime.status == 'RELEASING' &&
        widget.anime.nextAiringEpisode != null) {
      return widget.anime.nextAiringEpisode!.episode - 1;
    }
    return widget.anime.episodes ?? 12;
  }

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
          _NavBar(anime: widget.anime),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _LeftSidebar(anime: widget.anime)),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppPalette.border,
                ),
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
          MouseRegion(
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
                  // ── FIXED: AppPalette.transparent ──
                  color: _backHovered
                      ? AppPalette.border
                      : AppPalette.transparent,
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
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: AppPalette.border,
          ),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: AppNetworkImage(
                  url: anime.coverImage?.extraLarge ?? anime.bannerImage,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              anime.title.romaji ?? anime.title.english ?? 'Unknown Title',
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
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
// ════════════════════════════════════════════════════════════════════════════

class _EpisodePanel extends StatelessWidget {
  final int episodeCount;
  final int expandedEpisode;
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
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: episodeCount,
            itemBuilder: (context, index) {
              final ep = index + 1;
              return EpisodeTile(
                key: ValueKey(ep),
                episodeNumber: ep,
                isExpanded: expandedEpisode == ep,
                torrentFuture: expandedEpisode == ep ? futureFor(ep) : null,
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
//  _MetaChip
// ════════════════════════════════════════════════════════════════════════════

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
