import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../shared/widgets/frosted_container.dart';
import 'torrent_tile.dart';

/// Centered-card modal showing torrent search results for one episode.
///
/// The full-screen glassmorphic backdrop lives inside this widget's own
/// build(), routed through FrostedContainer (blur in normal mode, flat
/// scrim under uiPerformanceMode, matching every other glass surface in
/// the app) rather than using showGeneralDialog's plain-color
/// `barrierColor`.
///
/// One consequence worth calling out: because this backdrop is a real,
/// opaque widget painted in front of the (transparent) ModalBarrier,
/// tapping it can't rely on barrierDismissible's own built-in gesture
/// handling — that gesture lives on the barrier behind this backdrop,
/// which the backdrop would otherwise silently intercept. The backdrop
/// below carries its own onTap-to-dismiss instead. The centered card is
/// a Stack sibling painted after (on top of) the backdrop, so a tap on
/// the card itself is consumed by the card's own opaque decoration first
/// and never reaches the backdrop's dismiss handler underneath.
///
/// Selecting a torrent pops this route with that [Torrent] as the result
/// — the modal closes itself rather than exposing a separate
/// onSelectTorrent callback for the caller to act on and then pop
/// manually. [show] returns null if the modal is dismissed (backdrop tap,
/// close button, or system back) without a selection. Callers must await
/// [show] before pushing any new route on the same Navigator: since this
/// is an animated ModalRoute, popping it doesn't remove it from the
/// Overlay synchronously, and pushing a new route before that exit
/// finishes races the two routes' Overlay entries against each other.
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
    return showGeneralDialog<Torrent?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Episode $episodeNumber sources',
      // Transparent — the darkening lives entirely in this widget's own
      // full-screen backdrop below, via FrostedContainer. See class doc
      // for why the dismiss gesture lives there too.
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
    return Stack(
      children: [
        // Full-screen glassmorphic backdrop — see class doc for both the
        // blur-mode rationale and the tap-to-dismiss handoff.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: FrostedContainer(
              uiPerformanceMode: uiPerformanceMode,
              sigma: context.appMaterials.prominent,
              child: Container(
                color: AppPalette.black.withValues(
                  alpha: uiPerformanceMode ? 0.85 : 0.55,
                ),
              ),
            ),
          ),
        ),

        DpadRegion(
          memoryKey: 'animeDetails.torrentModal.$episodeNumber',
          child: Center(
            child: FrostedContainer(
              uiPerformanceMode: uiPerformanceMode,
              sigma: context.appMaterials.standard,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 520,
                constraints: const BoxConstraints(maxHeight: 560),
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
                        style: TextStyle(
                          color: AppPalette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Divider(color: AppPalette.border, height: 1),
                    Flexible(
                      child: FutureBuilder<List<Torrent>>(
                        future: torrentsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
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
                              message:
                                  'No seeded torrents found for this episode.',
                            );
                          }
                          return _ResultsList(
                            torrents: torrents,
                            uiPerformanceMode: uiPerformanceMode,
                            onSelectTorrent: (torrent) =>
                                Navigator.of(context).pop(torrent),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
