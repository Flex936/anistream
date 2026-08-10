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
///  - mpv's own decode pipeline: `estimated-frame-number` (the live
///    current-frame index) was confirmed climbing at the correct rate
///    while the on-screen picture was directly confirmed still frozen.
///    mpv is genuinely decoding new frames — nothing is reaching the
///    display.
///
/// A first iteration of this mitigation issued a same-position
/// `player.seek()` on resume, on the theory that a seek forces mpv to
/// flush and re-present through its render API. On-device testing
/// disproved that: manually scrubbing the seekbar after the freeze
/// reproduced doesn't restore the picture either, which means the stuck
/// state doesn't live anywhere a seek can reach — the seek/demux/decode
/// path was already confirmed healthy above, so a seek was never going
/// to touch whatever's actually stuck downstream of it.
///
/// This version instead cycles the `hwdec` property off and back to its
/// prior value. Unlike a seek, changing `hwdec` while a file is loaded
/// forces mpv to tear down and reconfigure the entire video chain
/// (decoder → vo) from scratch, which is a materially different reset
/// than anything a seek touches — the next actionable lever before
/// escalating to rebuilding the `VideoController`/`Video` widget
/// entirely (a heavier, visibly-flickering fallback held in reserve).
/// Root-causing/fixing the underlying bug natively is out of scope for
/// this Dart/Flutter codebase — it would live in media_kit_video's
/// plugin internals, the Flutter Linux embedder, or the NVIDIA driver
/// itself.
///
/// Status: unverified — this mechanism has not yet been confirmed to
/// resolve the freeze on real affected hardware. Opt-in only (see
/// [isEnabled]) for the same reason as before: confirmed reproducing
/// only on Linux + NVIDIA + Wayland, and cycling hwdec is a more
/// noticeable interruption (a brief decoder reinit stutter) than the
/// same-position seek this replaces, so it should never fire for anyone
/// who hasn't deliberately opted in.
class PlaybackFreezeWorkaroundController {
  final Player player;

  /// Reads the live `AppSettings.nudgeSeekOnResume` value — a function
  /// rather than a captured bool so a mid-session settings change takes
  /// effect without reconstructing this controller, matching
  /// `AutoSkipController.isEnabled`'s existing pattern. The setting's
  /// name still reflects the original seek-based mechanism; renaming it
  /// (and its persisted SharedPreferences key) is deliberately deferred
  /// until the hwdec-cycle approach is confirmed to actually work — no
  /// point renaming a setting twice if this iteration also needs to be
  /// replaced.
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

    unawaited(_cycleHwdec(pauseDuration));
  }

  /// Reads the current `hwdec` value, sets it to `'no'` (software
  /// decoding), then immediately restores the original value. Forces
  /// mpv to fully tear down and reconfigure the decode/vo chain rather
  /// than just moving the playback position — see the class doc for why
  /// this is expected to reach a different failure point than the
  /// same-position seek this replaces.
  Future<void> _cycleHwdec(Duration pauseDuration) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    try {
      final currentHwdec = await platform.getProperty('hwdec');
      AppLogger.i(
        'PlaybackFreezeWorkaround',
        'Cycling hwdec ($currentHwdec) after ${pauseDuration.inSeconds}s pause',
      );
      await platform.setProperty('hwdec', 'no');
      await platform.setProperty('hwdec', currentHwdec);
    } catch (e) {
      // mpv property read/write can fail if the engine's mid-teardown or
      // the property is momentarily unavailable — not worth surfacing
      // to the user over, but logged so a future diagnostic pass can see
      // it happened.
      AppLogger.w('PlaybackFreezeWorkaround', 'hwdec cycle failed: $e');
    }
  }

  void dispose() {
    unawaited(_playingSub.cancel());
  }
}
