import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../../core/logging/app_logger.dart';

/// Workaround for a confirmed but unfixable-from-here video freeze bug in
/// `media_kit_video`'s libmpv render-API texture hand-off on Linux (NVIDIA
/// + Wayland — `hwdec-current=nvdec`, `current-vo=libmpv`) after the
/// GL/EGL context has sat idle through an extended pause (confirmed
/// reproducing at ~20-56 minute pauses).
///
/// Diagnostic investigation (a temporary `PlaybackDiagnostics` class
/// polling mpv properties via `NativePlayer.getProperty` around
/// pause/resume/seek) ruled out every other layer before landing here:
///  - Network/HTTP stream health: `demuxer-cache-time` reliably grows on
///    resume across every reproduction.
///  - Demuxer/cache: `core-idle`/`demuxer-cache-idle` transition
///    correctly; `cache-buffering-state` stays at 100%.
///  - App focus/lifecycle: reproduced with the window holding focus
///    continuously through the whole pause.
///  - Fullscreen state: froze in both windowed and fullscreen.
///  - mpv's own decode pipeline: the decisive test —
///    `estimated-frame-number` (the live current-frame index; NOT the
///    static per-file `estimated-frame-count`, an earlier-round red
///    herring) was confirmed climbing at ~24fps, matching elapsed
///    wall-clock time, for 5+ seconds after a resume where the on-screen
///    picture was directly confirmed still frozen. mpv is genuinely
///    decoding new frames — nothing is reaching the display.
///
/// Root-causing/fixing this natively is out of scope for this Dart/Flutter
/// codebase — it would live in media_kit_video's plugin internals, the
/// Flutter Linux embedder, or the NVIDIA driver itself. The mitigation
/// applied here — a same-position seek on resume, which forces mpv to
/// flush and re-present through its render API from scratch — is a
/// well-established workaround for "decoder's fine, presented texture is
/// stuck" bugs in other GL-embedded players, not a real fix.
///
/// Opt-in only (see [isEnabled]) — confirmed reproducing only on Linux +
/// NVIDIA + Wayland, not on Windows + Intel iGPU. Any pause-duration gate
/// short enough to catch this bug is also short enough to fire on
/// completely ordinary pauses (answering the door, a phone call), so a
/// default-on mitigation would cost every unaffected user a small,
/// purposeless stutter for a bug they can never hit.
class PlaybackFreezeWorkaroundController {
  final Player player;

  /// Reads the live `AppSettings.nudgeSeekOnResume` value — a function
  /// rather than a captured bool so a mid-session settings change takes
  /// effect without reconstructing this controller, matching
  /// `AutoSkipController.isEnabled`'s existing pattern.
  final bool Function() isEnabled;

  /// Internal-only — deliberately NOT user-configurable. The opt-in
  /// toggle itself is the only decision surface that matters here; a
  /// shorter gate would start firing on ordinary short pauses even for
  /// users who've opted in.
  static const Duration _kMinPauseDuration = Duration(seconds: 60);

  DateTime? _pauseStartedAt;
  late final StreamSubscription<bool> _playingSub;

  PlaybackFreezeWorkaroundController({
    required this.player,
    required this.isEnabled,
  }) {
    _playingSub = player.stream.playing.listen(_onPlayingChanged);
  }

  void _onPlayingChanged(bool playing) {
    if (!playing) {
      _pauseStartedAt = DateTime.now();
      return;
    }

    // Transition back to playing — consume whatever pause start we have,
    // regardless of outcome, so a stale timestamp never lingers into a
    // later pause/resume cycle.
    final pausedAt = _pauseStartedAt;
    _pauseStartedAt = null;
    if (pausedAt == null) return;
    if (!isEnabled()) return;

    final pauseDuration = DateTime.now().difference(pausedAt);
    if (pauseDuration < _kMinPauseDuration) return;

    AppLogger.i(
      'PlaybackFreezeWorkaround',
      'Nudge-seeking after ${pauseDuration.inSeconds}s pause',
    );
    // Player.seek returns Future<void> — this is called from a
    // synchronous stream listener callback, so the fire-and-forget intent
    // is made explicit instead of silently dropped (unawaited_futures).
    unawaited(player.seek(player.state.position));
  }

  void dispose() {
    unawaited(_playingSub.cancel());
  }
}
