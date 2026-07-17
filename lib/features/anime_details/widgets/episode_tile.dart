import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../shared/widgets/hover_focus_builder.dart';
import '../../theater/theater_screen.dart';
import 'torrent_tile.dart';

class EpisodeTile extends StatelessWidget {
  final Anime anime;
  final int episodeNumber;
  final bool isExpanded;
  final int? userProgress;
  final bool isUpNext;
  final Future<List<Torrent>>? torrentFuture;
  final VoidCallback onToggle;
  final VoidCallback? onReturnFromTheater;
  final bool isAutoPlayEnabled;
  final bool isCurrentlyLoading;
  final bool uiPerformanceMode;

  const EpisodeTile({
    super.key,
    required this.anime,
    required this.episodeNumber,
    required this.isExpanded,
    this.userProgress,
    this.isUpNext = false,
    this.torrentFuture,
    required this.onToggle,
    this.onReturnFromTheater,
    this.isAutoPlayEnabled = false,
    this.isCurrentlyLoading = false,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final hPad = isMobile ? 16.0 : 28.0;

    final isWatched = userProgress != null && episodeNumber <= userProgress!;

    final Color numColor = isExpanded
        ? AppPalette.primary
        : isUpNext
        ? AppPalette.textMain
        : isWatched
        ? AppPalette.textMuted.withValues(alpha: 0.25)
        : AppPalette.textMuted.withValues(alpha: 0.35);

    final Color titleColor = isExpanded || isUpNext
        ? AppPalette.textMain
        : isWatched
        ? AppPalette.textMuted.withValues(alpha: 0.5)
        : AppPalette.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HoverFocusBuilder(
          autofocus: isUpNext || (userProgress == null && episodeNumber == 1),
          onTap: onToggle,
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 15),
            decoration: BoxDecoration(
              color: isExpanded
                  ? AppPalette.primary.withValues(alpha: 0.06)
                  : hovered
                  ? AppPalette.white.withValues(alpha: 0.025)
                  : AppPalette.transparent,
              border: Border(
                left: BorderSide(
                  color: isExpanded
                      ? AppPalette.primary
                      : isUpNext
                      ? AppPalette.primary.withValues(alpha: 0.3)
                      : AppPalette.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: isMobile ? 26 : 34,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      episodeNumber.toString().padLeft(2, '0'),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: numColor,
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Episode $episodeNumber',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 14,
                          fontWeight: isExpanded || isUpNext
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (isUpNext) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'UP NEXT',
                            style: TextStyle(
                              color: AppPalette.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      if (isWatched) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: AppPalette.textMuted.withValues(alpha: 0.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isCurrentlyLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppPalette.primary,
                      ),
                    ),
                  )
                else if (isAutoPlayEnabled)
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 24,
                    color: hovered
                        ? AppPalette.primary
                        : AppPalette.textMuted.withValues(alpha: 0.5),
                  )
                else
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: isExpanded
                          ? AppPalette.primary
                          : AppPalette.textMuted.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? _buildTorrentContent(context, hPad)
              : const SizedBox.shrink(),
        ),
        const Divider(height: 1, thickness: 1, color: AppPalette.border),
      ],
    );
  }

  Widget _buildTorrentContent(BuildContext context, double hPad) {
    final future = torrentFuture;
    if (future == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 16),
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
                  uiPerformanceMode: uiPerformanceMode,
                  onStream: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TheaterScreen(
                          anime: anime,
                          episode: episodeNumber,
                          torrent: torrents[i],
                        ),
                      ),
                    ).then((_) => onReturnFromTheater?.call());
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
