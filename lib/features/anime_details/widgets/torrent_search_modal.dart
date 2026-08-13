import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/input/input_mode_scope.dart';
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
class TorrentSearchModal extends StatelessWidget {
  final int episodeNumber;
  final Future<List<Torrent>> torrentsFuture;
  final bool uiPerformanceMode;

  const TorrentSearchModal({
    super.key,
    required this.episodeNumber,
    required this.torrentsFuture,
    this.uiPerformanceMode = false,
  });

  static Future<Torrent?> show({
    required BuildContext context,
    required int episodeNumber,
    required Future<List<Torrent>> torrentsFuture,
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
  Widget build(BuildContext context) {
    return SelectionModal(
      icon: Icons.search_rounded,
      title: 'Episode $episodeNumber',
      subtitle: 'Choose a release to stream, sorted by best match.',
      regionMemoryKey: 'animeDetails.torrentModal.$episodeNumber',
      uiPerformanceMode: uiPerformanceMode,
      // Both pop with no result (null) — a plain dismiss, not a selection.
      onClose: () => Navigator.of(context).pop(),
      onBackdropTap: () => Navigator.of(context).pop(),
      body: FutureBuilder<List<Torrent>>(
        future: torrentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingState();
          }
          if (snapshot.hasError) {
            return _ErrorState(message: _messageFor(snapshot.error));
          }
          final torrents = snapshot.data ?? const <Torrent>[];
          if (torrents.isEmpty) {
            return const _ErrorState(
              message: 'No seeded torrents found for this episode.',
            );
          }
          return _ResultsList(
            torrents: torrents,
            uiPerformanceMode: uiPerformanceMode,
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
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final dpadModeActive = context.dpadModeActive;
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
          DpadFocusable(
            autofocus: dpadModeActive,
            onSelect: () => Navigator.of(context).pop(),
            builder: (context, state, child) {
              final bool visuallyFocused = state.focused && dpadModeActive;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: visuallyFocused
                      ? AppPalette.primary.withValues(alpha: 0.15)
                      : AppPalette.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: visuallyFocused
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
              );
            },
            child: const SizedBox.shrink(),
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
