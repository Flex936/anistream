import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/settings/settings_service.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../data/torrent/models/torrent.dart';
import '../../../data/torrent/torrent_scraper_service.dart';
import 'remote_streaming_controller.dart';
import 'streaming_controller.dart';
import 'streaming_controller_base.dart';

/// Builds the [BaseStreamingController] [settings] selects: remote when server
/// mode has a URL, else on-device. Shared with `TheaterScreen` so the two
/// paths can't drift.
BaseStreamingController createStreamingController(AppSettings settings) {
  return settings.serverMode && settings.serverUrl.isNotEmpty
      ? RemoteStreamingController(serverUrl: settings.serverUrl)
      : StreamingController();
}

/// A buffering Tier 2 controller and its torrent; see
/// [NextEpisodePrefetchController.takeWarmResult].
typedef WarmStreamingResult = ({
  BaseStreamingController controller,
  Torrent torrent,
});

/// Prefetches the next episode's torrents (Tier 1) and, with autoplay on, a
/// warm streaming session (Tier 2). One instance per `TheaterScreen`, fed by
/// its position listener via [onPosition]. See ARCHITECTURE.md § 5.
class NextEpisodePrefetchController {
  final Anime anime;
  final int nextEpisode;
  final AppSettings settings;

  /// Read live at arm time, not captured at construction.
  final bool Function() episodeAutoplayEnabled;

  /// Fired at most once, when Tier 2 first becomes ready to play.
  final VoidCallback? onEngineWarm;

  final TorrentScraperService _scraper;

  NextEpisodePrefetchController({
    required this.anime,
    required this.nextEpisode,
    required this.settings,
    required this.episodeAutoplayEnabled,
    this.onEngineWarm,
    TorrentScraperService? scraper,
  }) : _scraper = scraper ?? TorrentScraperService();

  /// Fraction of the episode played before Tier 1 arms; below the Next Episode
  /// chip's 95% so prefetch gets a head start.
  static const double _kArmThreshold = 0.85;

  bool _armed = false;
  bool _disposed = false;
  bool _hasNotifiedWarm = false;

  BaseStreamingController? _engineController;
  Torrent? _engineTorrent;

  /// True once Tier 2's controller is ready to play; see [takeWarmResult].
  bool get isEngineWarm =>
      _engineController != null &&
      _engineTorrent != null &&
      _engineController!.isReadyToPlay;

  /// Call on each position tick; no-ops once armed or after [dispose].
  void onPosition(Duration position, Duration duration) {
    if (_armed || _disposed) return;
    if (duration <= Duration.zero) return;

    final percent = position.inMilliseconds / duration.inMilliseconds;
    if (percent < _kArmThreshold) return;

    _armed = true;
    unawaited(_runTier1());
  }

  Future<void> _runTier1() async {
    final List<Torrent> torrents;
    try {
      torrents = await _scraper.fetchTorrents(anime, nextEpisode);
    } catch (e, st) {
      // "No seeded torrents" (thrown) or a scrape failure: nothing to warm.
      AppLogger.e(
        'NextEpisodePrefetchController',
        'Tier 1 search failed for episode $nextEpisode',
        e,
        st,
      );
      return;
    }

    if (_disposed || torrents.isEmpty) return;

    if (episodeAutoplayEnabled()) {
      unawaited(_runTier2(torrents.first));
    }
  }

  Future<void> _runTier2(Torrent topTorrent) async {
    if (_disposed) return;

    final controller = createStreamingController(settings);
    _engineController = controller;
    _engineTorrent = topTorrent;
    controller.addListener(_onEngineStateChanged);

    try {
      await controller.initialize(
        topTorrent.magnetLink,
        episodeNumber: nextEpisode,
      );
    } catch (e, st) {
      AppLogger.e(
        'NextEpisodePrefetchController',
        'Tier 2 warm-up failed for episode $nextEpisode',
        e,
        st,
      );
      _discardEngineController();
    }
  }

  void _onEngineStateChanged() {
    if (_disposed) return;
    final controller = _engineController;
    if (controller == null) return;

    // An unmatched batch counts as a failure: discard it, and the transition
    // falls back to autoFetch/manualPick.
    if (controller.needsManualSelection || controller.hasError) {
      _discardEngineController();
      return;
    }

    if (controller.isReadyToPlay && !_hasNotifiedWarm) {
      _hasNotifiedWarm = true;
      onEngineWarm?.call();
    }
  }

  void _discardEngineController() {
    final controller = _engineController;
    _engineController = null;
    _engineTorrent = null;
    if (controller != null) {
      controller.removeListener(_onEngineStateChanged);
      controller.dispose();
    }
  }

  /// Hands the warm controller and torrent to the caller, or null if Tier 2
  /// isn't ready. The caller owns the controller; [dispose] won't touch it.
  WarmStreamingResult? takeWarmResult() {
    if (!isEngineWarm) return null;

    final result = (controller: _engineController!, torrent: _engineTorrent!);
    _engineController!.removeListener(_onEngineStateChanged);
    _engineController = null;
    _engineTorrent = null;
    return result;
  }

  /// Disposes a Tier 2 controller not taken via [takeWarmResult]; idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _discardEngineController();
    _scraper.dispose();
  }
}
