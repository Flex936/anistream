import 'package:flutter/material.dart';

import '../screens/theater_screen.dart';
import '../services/torrent_scraper.dart';
import '../theme/app_palette.dart';
import 'torrent_tile.dart';

class EpisodeTile extends StatefulWidget {
  final int episodeNumber;
  final bool isExpanded;

  /// Non-null only when [isExpanded] is true; guards the FutureBuilder.
  final Future<List<Torrent>>? torrentFuture;
  final VoidCallback onToggle;

  const EpisodeTile({
    super.key,
    required this.episodeNumber,
    required this.isExpanded,
    this.torrentFuture,
    required this.onToggle,
  });

  @override
  State<EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<EpisodeTile> {
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
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: widget.isExpanded
              ? _buildTorrentContent()
              : const SizedBox.shrink(),
        ),

        const Divider(height: 1, thickness: 1, color: AppPalette.border),
      ],
    );
  }

  Widget _buildTorrentContent() {
    final future = widget.torrentFuture;
    if (future == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: FutureBuilder<List<Torrent>>(
        future: future,
        builder: (context, snapshot) {
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

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              for (int i = 0; i < torrents.length; i++) ...[
                TorrentTile(
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
