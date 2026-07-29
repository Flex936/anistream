import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../shared/widgets/hover_focus_builder.dart';
import '../../theater/theater_screen.dart';
import 'torrent_tile.dart';

class EpisodeTile extends StatefulWidget {
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
  State<EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<EpisodeTile> {
  // ── Expansible requires a persistent ExpansibleController (a
  // ChangeNotifier with its own dispose() contract) — this is the reason
  // this widget moved from Stateless to Stateful. Expansion state itself
  // is still NOT owned here: `widget.isExpanded` remains driven entirely
  // by AnimeDetailsScreen's `_expandedEpisode` single-int accordion index,
  // exactly as before. This controller exists purely to satisfy
  // Expansible's API contract and is kept in lockstep with
  // `widget.isExpanded` via didUpdateWidget below — it never originates a
  // state change of its own; the header's tap still goes straight to
  // `widget.onToggle` (the external callback), same as before. ──
  late final ExpansibleController _expansibleController;

  @override
  void initState() {
    super.initState();
    _expansibleController = ExpansibleController();
    if (widget.isExpanded) {
      _expansibleController.expand();
    }
  }

  @override
  void didUpdateWidget(covariant EpisodeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _expansibleController.expand();
      } else {
        _expansibleController.collapse();
      }
    }
  }

  @override
  void dispose() {
    _expansibleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Routed through the shared ResponsiveContext.isMobile
    // extension instead of a raw MediaQuery check. ──
    final isMobile = context.isMobile;
    final hPad = isMobile ? 16.0 : 28.0;

    final isWatched =
        widget.userProgress != null &&
        widget.episodeNumber <= widget.userProgress!;

    final Color numColor = widget.isExpanded
        ? AppPalette.primary
        : widget.isUpNext
        ? AppPalette.textMain
        : isWatched
        ? AppPalette.textMuted.withValues(alpha: 0.25)
        : AppPalette.textMuted.withValues(alpha: 0.35);

    final Color titleColor = widget.isExpanded || widget.isUpNext
        ? AppPalette.textMain
        : isWatched
        ? AppPalette.textMuted.withValues(alpha: 0.5)
        : AppPalette.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expansible(
          controller: _expansibleController,
          // ── Matches the previous AnimatedRotation/AnimatedSize timing
          // (250ms, easeOutCubic) instead of Expansible's own default
          // (200ms, Curves.ease), so the motion feels the same as before. ──
          animationStyle: const AnimationStyle(
            duration: Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
          headerBuilder: (context, animation) => _buildHeader(
            animation: animation,
            hPad: hPad,
            isMobile: isMobile,
            numColor: numColor,
            titleColor: titleColor,
            isWatched: isWatched,
          ),
          // ── The Divider stays OUTSIDE Expansible entirely (see below) —
          // it was always visible regardless of expand state in the
          // original, never part of the collapsible AnimatedSize. ──
          bodyBuilder: (context, animation) =>
              _buildTorrentContent(context, hPad),
        ),
        const Divider(height: 1, thickness: 1, color: AppPalette.border),
      ],
    );
  }

  Widget _buildHeader({
    required Animation<double> animation,
    required double hPad,
    required bool isMobile,
    required Color numColor,
    required Color titleColor,
    required bool isWatched,
  }) {
    return HoverFocusBuilder(
      autofocus:
          widget.isUpNext ||
          (widget.userProgress == null && widget.episodeNumber == 1),
      onTap: widget.onToggle,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 15),
        decoration: BoxDecoration(
          color: widget.isExpanded
              ? AppPalette.primary.withValues(alpha: 0.06)
              : hovered
              ? AppPalette.white.withValues(alpha: 0.025)
              : AppPalette.transparent,
          border: Border(
            left: BorderSide(
              color: widget.isExpanded
                  ? AppPalette.primary
                  : widget.isUpNext
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
                  widget.episodeNumber.toString().padLeft(2, '0'),
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
                    'Episode ${widget.episodeNumber}',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: widget.isExpanded || widget.isUpNext
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  if (widget.isUpNext) ...[
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
            if (widget.isCurrentlyLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
                ),
              )
            else if (widget.isAutoPlayEnabled)
              Icon(
                Icons.play_arrow_rounded,
                size: 24,
                color: hovered
                    ? AppPalette.primary
                    : AppPalette.textMuted.withValues(alpha: 0.5),
              )
            else
              // ── Was AnimatedRotation(turns: isExpanded ? 0.5 : 0.0,
              // duration: 250ms, curve: easeOutCubic, ...) driven by a
              // manually-tracked bool. Now a RotationTransition driven
              // directly off Expansible's own animation (0 -> 1 as it
              // expands/collapses), scaled to a half turn via a Tween —
              // same 0 -> 180° sweep, same curve/duration (set via
              // animationStyle above), just sourced from the single
              // shared Expansible animation instead of a second,
              // independently-timed AnimatedRotation. Icon color is
              // still a plain immediate switch on widget.isExpanded, not
              // animated — matches the original exactly (only the
              // rotation was ever animated, never the color). ──
              RotationTransition(
                turns: Tween<double>(begin: 0.0, end: 0.5).animate(animation),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: widget.isExpanded
                      ? AppPalette.primary
                      : AppPalette.textMuted.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTorrentContent(BuildContext context, double hPad) {
    final future = widget.torrentFuture;
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
                  uiPerformanceMode: widget.uiPerformanceMode,
                  onStream: () {
                    unawaited(
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TheaterScreen(
                            anime: widget.anime,
                            episode: widget.episodeNumber,
                            torrent: torrents[i],
                          ),
                        ),
                      ).then((_) => widget.onReturnFromTheater?.call()),
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
