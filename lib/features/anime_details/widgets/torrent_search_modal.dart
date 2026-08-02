import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../shared/widgets/frosted_container.dart';
import 'torrent_tile.dart';

/// Centered-card modal showing torrent search results for one episode —
/// the sibling pattern to [BatchEpisodePickerOverlay], but routed via
/// [showGeneralDialog] (same mechanism as [SettingsMenu]/
/// [SearchFilterPanel]) rather than an inline Stack overlay, since it
/// doesn't need BatchEpisodePickerOverlay's manual onBack wiring — D-pad
/// Back, Escape, and the system back gesture all dismiss it for free
/// through the Navigator/PopScope chain already threaded through app.dart.
///
/// Takes the SAME [Future] [AnimeDetailsScreen] already memoizes per
/// episode rather than starting its own search — including one that's
/// already settled by the time this opens, which is what lets autoplay's
/// silent failure surface here immediately (no duplicate network request)
/// instead of falling back to an inline expansion the way it used to.
///
/// [torrentsFuture] failing OR resolving to a defensively-empty list are
/// both routed through the same error UI — see [_ErrorState] — so there
/// is exactly one place in this screen that ever shows a "search didn't
/// work out" message, and it's always this modal, never inline in a list
/// item.
class TorrentSearchModal extends StatelessWidget {
  final int episodeNumber;
  final Future<List<Torrent>> torrentsFuture;
  final void Function(Torrent torrent) onSelectTorrent;
  final bool uiPerformanceMode;

  const TorrentSearchModal({
    super.key,
    required this.episodeNumber,
    required this.torrentsFuture,
    required this.onSelectTorrent,
    this.uiPerformanceMode = false,
  });

  static Future<void> show({
    required BuildContext context,
    required int episodeNumber,
    required Future<List<Torrent>> torrentsFuture,
    required void Function(Torrent torrent) onSelectTorrent,
    bool uiPerformanceMode = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Episode $episodeNumber sources',
      barrierColor: AppPalette.black.withValues(alpha: 0.50),
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
        onSelectTorrent: onSelectTorrent,
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
    return DpadRegion(
      memoryKey: 'animeDetails.torrentModal.$episodeNumber',
      child: Center(
        child: FrostedContainer(
          uiPerformanceMode: uiPerformanceMode,
          sigma: 16,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 440,
            constraints: const BoxConstraints(maxHeight: 480),
            decoration: BoxDecoration(
              color: AppPalette.surface.withValues(
                alpha: uiPerformanceMode ? 0.98 : 0.90,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppPalette.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(episodeNumber: episodeNumber),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Choose a release to stream, sorted by best match.',
                    style: TextStyle(color: AppPalette.textMuted, fontSize: 13),
                  ),
                ),
                const Divider(color: AppPalette.border, height: 1),
                Flexible(
                  child: FutureBuilder<List<Torrent>>(
                    future: torrentsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const _LoadingState();
                      }
                      if (snapshot.hasError) {
                        return _ErrorState(
                          message: _messageFor(snapshot.error),
                        );
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
                        onSelectTorrent: onSelectTorrent,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int episodeNumber;
  const _Header({required this.episodeNumber});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppPalette.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Episode $episodeNumber',
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DpadFocusable(
            onSelect: () => Navigator.of(context).pop(),
            builder: (context, state, child) => Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: state.focused
                    ? AppPalette.white.withValues(alpha: 0.1)
                    : AppPalette.transparent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: AppPalette.textMuted,
                size: 20,
              ),
            ),
            child: const SizedBox.shrink(),
          ),
        ],
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

/// Covers BOTH a thrown [Exception] from the scraper AND a defensively
/// empty (but non-throwing) result list under one rendering path — see
/// [TorrentSearchModal]'s class doc for why that consolidation matters.
class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

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
          // ── Autofocused — the state's single interactive target, same
          // convention as BatchEpisodePickerOverlay's first-row autofocus. ──
          DpadFocusable(
            autofocus: true,
            onSelect: () => Navigator.of(context).pop(),
            builder: (context, state, child) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: state.focused
                    ? AppPalette.primary.withValues(alpha: 0.15)
                    : AppPalette.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: state.focused ? AppPalette.primary : AppPalette.border,
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
    );
  }
}

class _ResultsList extends StatelessWidget {
  final List<Torrent> torrents;
  final bool uiPerformanceMode;
  final void Function(Torrent torrent) onSelectTorrent;

  const _ResultsList({
    required this.torrents,
    required this.uiPerformanceMode,
    required this.onSelectTorrent,
  });

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
          onStream: () => onSelectTorrent(torrents[i]),
        );
      },
    );
  }
}
