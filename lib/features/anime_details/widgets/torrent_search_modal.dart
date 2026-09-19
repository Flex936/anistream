import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../shared/widgets/selection_modal.dart';
import 'torrent_tile.dart';

/// Centered-card modal showing torrent search results for one episode.
///
/// Built on [SelectionModal] — see that widget's doc comment for the
/// shared chrome this and [BatchEpisodePickerOverlay] both use. Mounted
/// as a real pushed route via [show]; the resolved [Future] carries the
/// user's chosen [Torrent], or `null` if the modal was dismissed without
/// a selection (backdrop tap, close button, or the error state's Close
/// button) — the standard `showDialog<T>`-style contract, rather than a
/// callback invoked while the route is still open.
///
/// Holds the currently-active search [Future] as local state rather than
/// as a plain constructor field: [onRetry] lets the error/empty state
/// swap in a freshly-fetched Future without popping and re-pushing this
/// route, which would replay [SelectionModal]'s entrance transition for
/// what should read as a seamless in-place refresh instead.
class TorrentSearchModal extends StatefulWidget {
  final int episodeNumber;
  final Future<List<Torrent>> torrentsFuture;
  final Future<List<Torrent>> Function() onRetry;
  final bool uiPerformanceMode;

  const TorrentSearchModal({
    super.key,
    required this.episodeNumber,
    required this.torrentsFuture,
    required this.onRetry,
    this.uiPerformanceMode = false,
  });

  static Future<Torrent?> show({
    required BuildContext context,
    required int episodeNumber,
    required Future<List<Torrent>> torrentsFuture,
    required Future<List<Torrent>> Function() onRetry,
    bool uiPerformanceMode = false,
  }) {
    return showGeneralDialog<Torrent>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Episode $episodeNumber sources',
      // Transparent — the darkening lives entirely in SelectionModal's
      // own full-screen backdrop. See that widget's doc for why the
      // dismiss gesture lives there too.
      barrierColor: AppPalette.transparent,
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, _, _) => TorrentSearchModal(
        episodeNumber: episodeNumber,
        torrentsFuture: torrentsFuture,
        onRetry: onRetry,
        uiPerformanceMode: uiPerformanceMode,
      ),
    );
  }

  static String _messageFor(Object? error) {
    final raw = error?.toString() ?? 'Something went wrong while searching.';
    const prefix = 'Exception: ';
    return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
  }

  @override
  State<TorrentSearchModal> createState() => _TorrentSearchModalState();
}

class _TorrentSearchModalState extends State<TorrentSearchModal> {
  late Future<List<Torrent>> _activeFuture;

  @override
  void initState() {
    super.initState();
    _activeFuture = widget.torrentsFuture;
  }

  // Swaps in a freshly-fetched Future from widget.onRetry — FutureBuilder
  // resets to its loading branch the instant the Future instance it's
  // given changes, so this alone is what takes the body from _ErrorState
  // back through _LoadingState to either _ErrorState or _ResultsList
  // again, with no route pop/push involved.
  void _handleRetry() {
    setState(() => _activeFuture = widget.onRetry());
  }

  @override
  Widget build(BuildContext context) {
    return SelectionModal(
      icon: Icons.search_rounded,
      title: 'Episode ${widget.episodeNumber}',
      subtitle: 'Choose a release to stream, sorted by best match.',
      regionMemoryKey: 'animeDetails.torrentModal.${widget.episodeNumber}',
      uiPerformanceMode: widget.uiPerformanceMode,
      // Both pop with no result (null) — a plain dismiss, not a selection.
      onClose: () => Navigator.of(context).pop(),
      onBackdropTap: () => Navigator.of(context).pop(),
      body: FutureBuilder<List<Torrent>>(
        future: _activeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingState();
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: TorrentSearchModal._messageFor(snapshot.error),
              onRetry: _handleRetry,
            );
          }
          final torrents = snapshot.data ?? const <Torrent>[];
          if (torrents.isEmpty) {
            return _ErrorState(
              message: 'No seeded torrents found for this episode.',
              onRetry: _handleRetry,
            );
          }
          return _ResultsList(
            torrents: torrents,
            uiPerformanceMode: widget.uiPerformanceMode,
          );
        },
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
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
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppPalette.textMuted,
            size: 40,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppPalette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primary action — holds the autofocus the Close button
              // used to hold, since retrying is the more useful default
              // than dismissing once a search has failed or come up empty.
              DpadFocusable(
                autofocus: true,
                onSelect: onRetry,
                builder: (context, state, child) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: state.focused
                        ? AppPalette.primaryHover
                        : AppPalette.primary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: state.focused
                          ? AppPalette.white
                          : AppPalette.primary,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: AppPalette.white,
                        size: 15,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Retry',
                        style: TextStyle(
                          color: AppPalette.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                child: const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              DpadFocusable(
                onSelect: () => Navigator.of(context).pop(),
                builder: (context, state, child) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: state.focused
                        ? AppPalette.primary.withValues(alpha: 0.15)
                        : AppPalette.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: state.focused
                          ? AppPalette.primary
                          : AppPalette.border,
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: AppPalette.textMain,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  final List<Torrent> torrents;
  final bool uiPerformanceMode;

  const _ResultsList({required this.torrents, required this.uiPerformanceMode});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: torrents.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        return TorrentTile(
          torrent: torrents[i],
          isRecommended: i == 0,
          autofocus: i == 0,
          uiPerformanceMode: uiPerformanceMode,
          // Pops the route with the chosen torrent as its result, rather
          // than invoking a callback while still on-screen — the caller
          // (AnimeDetailsScreen._openTorrentModal) awaits `show()` and
          // acts on the returned value after the modal is already gone.
          onStream: () => Navigator.of(context).pop(torrents[i]),
        );
      },
    );
  }
}
