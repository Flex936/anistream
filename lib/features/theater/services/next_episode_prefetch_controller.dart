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

/// Constructs the right [BaseStreamingController] implementation for
/// [settings] — [RemoteStreamingController] when server mode is on and a
/// URL is configured, [StreamingController] otherwise. Shared by
/// `TheaterScreen._initPlayerAndStream` (the current episode's own
/// controller) and this file's Tier 2 engine warm-up (the next episode's),
/// so the two paths can never independently drift on which controller
/// type a given settings combination resolves to.
BaseStreamingController createStreamingController(AppSettings settings) {
  return settings.serverMode && settings.serverUrl.isNotEmpty
      ? RemoteStreamingController(serverUrl: settings.serverUrl)
      : StreamingController();
}

/// Result of a successful Tier 2 engine warm-up — the torrent picked and
/// the already-buffering controller streaming it, ready for an instant
/// hand-off to the next episode's `TheaterScreen`. See
/// [NextEpisodePrefetchController.takeWarmResult].
typedef WarmStreamingResult = ({
  BaseStreamingController controller,
  Torrent torrent,
});

/// Background-prefetches the next episode's torrent sources — and, when
/// episode-autoplay is on, its actual streaming session — as the current
/// episode nears its end. Two independent tiers:
///
///  - **Tier 1 (always runs)**: resolves and scores candidate torrents
///    for the next episode via the existing [TorrentScraperService] — the
///    same isolate-backed parsing pipeline and TTL search cache every
///    other torrent search already goes through. Warms the picker even
///    when autoplay is off, so `TorrentSearchModal` opens with results
///    already resolved instead of a spinner.
///  - **Tier 2 (only when [episodeAutoplayEnabled] is true)**:
///    additionally constructs a real [BaseStreamingController] for the
///    top-scored result and starts buffering it, so an autoplay-driven
///    transition can hand off an already-warm stream instead of starting
///    from zero. Gated specifically on autoplay: committing bandwidth (or
///    a remote-server session) to one *particular* torrent only makes
///    sense once the app already knows it'll use that exact pick without
///    asking the user first.
///
/// One instance is owned per `TheaterScreen` and fed via the same
/// `Player.stream.position` listener that screen already has — see
/// [onPosition]. Never constructed at all when there's no next episode to
/// prefetch.
class NextEpisodePrefetchController {
  final Anime anime;
  final int nextEpisode;
  final AppSettings settings;

  /// Read live at arm time, not captured once at construction — mirrors
  /// `AutoSkipController.isEnabled`'s own shape for the same kind of
  /// settings-derived flag.
  final bool Function() episodeAutoplayEnabled;

  /// Fired at most once per instance, right when Tier 2 first reaches a
  /// ready-to-play state. Optional — `TheaterScreen` uses it to surface
  /// an "Up next" status toast through its existing notification
  /// mechanism, but nothing here depends on a listener being attached.
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

  /// Fraction of the current episode's duration crossed before Tier 1
  /// arms. Deliberately looser than `_PlaybackTimeline`'s 95% Next
  /// Episode chip threshold (`theater_controls.dart`) — prefetching
  /// starts quietly well before the chip has any reason to appear, so it
  /// has a head start by the time a transition might actually be
  /// requested.
  static const double _kArmThreshold = 0.85;

  bool _armed = false;
  bool _disposed = false;
  bool _hasNotifiedWarm = false;

  BaseStreamingController? _engineController;
  Torrent? _engineTorrent;

  /// True once Tier 2 has reached a ready-to-play state for the current
  /// [_engineController] — see [takeWarmResult].
  bool get isEngineWarm =>
      _engineController != null &&
      _engineTorrent != null &&
      _engineController!.isReadyToPlay;

  /// Call on every `Player.stream.position` tick, alongside whatever else
  /// that listener already does (AniList tracking, auto-skip). No-ops
  /// after the first arm for this instance, and after [dispose].
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
      // Covers both a genuine "no seeded torrents found" (which
      // fetchTorrents signals by throwing) and a transport/scrape
      // failure — either way there's nothing to warm, and the real,
      // visible flow will simply search again fresh when the user
      // actually reaches this episode.
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

    // A batch torrent that couldn't be confidently auto-matched to this
    // episode — never hand this off as an instant transition. The real,
    // visible flow's own batch picker is the right place to resolve
    // that, not a background prefetch the user never sees. Treated the
    // same as an outright failure: discard, and the eventual transition
    // falls back to autoFetch/manualPick same as if prefetch never ran.
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

  /// Consumes the Tier 2 result for an instant hand-off — returns `null`
  /// if Tier 2 never reached [isEngineWarm] (autoplay was off, it's still
  /// warming, or it failed). Relinquishes ownership of the returned
  /// controller to the caller: this instance will NOT dispose it, even
  /// when [dispose] is called on this instance afterward.
  WarmStreamingResult? takeWarmResult() {
    if (!isEngineWarm) return null;

    final result = (controller: _engineController!, torrent: _engineTorrent!);
    _engineController!.removeListener(_onEngineStateChanged);
    _engineController = null;
    _engineTorrent = null;
    return result;
  }

  /// Tears down anything still owned. A Tier 2 controller that was never
  /// consumed via [takeWarmResult] gets disposed here, bounding
  /// prefetch's worst-case resource use to "at most one episode ahead" —
  /// see the class doc comment. Idempotent: safe to call more than once,
  /// including after [takeWarmResult] already ran (nothing left to
  /// discard in that case) and regardless of how many of this screen's
  /// several teardown paths happen to call it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _discardEngineController();
    _scraper.dispose();
  }
}
