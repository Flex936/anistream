import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../../core/logging/app_logger.dart';

/// Track C, 3a: read-only diagnostic instrumentation for the permanent
/// frame-freeze bug reported after an extended PAUSE, where audio and the
/// seekbar/position both continue advancing normally on resume but the
/// displayed picture never updates again.
///
/// ── What's already been ruled out ──────────────────────────────────────
///
/// The first round of instrumentation here (demuxer/cache-only) was
/// cross-referenced against real device logs across two platforms and
/// confirmed the freeze is NOT a network/demuxer/cache problem: `core-idle`,
/// `demuxer-cache-idle`, `cache-buffering-state`, and `demuxer-cache-time`
/// all report a completely healthy resume — position advances at the
/// correct wall-clock rate and `demuxer-cache-time` visibly grows from a
/// fresh network read — on runs where the picture was independently
/// confirmed to be frozen. [PlayerConfigurator]'s HTTP reconnect tuning is
/// therefore not expected to be the fix for this specific symptom (it's
/// left in place regardless, since it's a reasonable hardening on its own
/// merits for a genuinely dropped connection, a distinct failure mode this
/// class doesn't rule out).
///
/// An `AppLifecycleState.inactive` transition landing near one early
/// resume was also considered as a possible trigger and has since been
/// ruled out — a later run reproduced the freeze with the window
/// confirmed to have held focus continuously through the entire pause.
///
/// Cross-platform testing narrowed this further: a ~17 minute pause on
/// Windows 11 with an Intel iGPU resumed and kept playing cleanly with no
/// freeze. The freeze has so far only been confirmed on Linux (Wayland
/// session, NVIDIA GPU, `hwdec-current=nvdec`), in both windowed and
/// fullscreen states, after pauses ranging from ~20 to ~55 minutes.
///
/// A second diagnostic pass added `estimated-frame-count` to try to catch
/// whether mpv's decode pipeline was still producing frames post-resume —
/// that property turned out to be the total frame count of the whole file
/// (a static, duration-derived constant), not a live decode-progress
/// counter, so it was uninformative and has been replaced below with
/// `estimated-frame-number` (the actual current/live frame index).
/// `vo-drop-frame-count` was also dropped — it returned empty on every
/// snapshot in that round, including during confirmed-healthy playback,
/// indicating it simply isn't populated for this vo/build.
///
/// ── What this round adds ───────────────────────────────────────────────
///
///  - `estimated-frame-number` — the live current-frame index. The actual
///    determining test: does this keep incrementing at [resume+2s]/
///    [resume+5s] (roughly `fps × elapsed seconds` higher than at
///    [resume]) despite the picture being independently confirmed frozen?
///    If yes, mpv's decode pipeline is fine and the break is specifically
///    in the Flutter/media_kit_video texture hand-off. If it's flat (or
///    barely moved) despite position/audio/cache all advancing normally,
///    that's confirmation the decoder itself has stalled — consistent
///    with a known class of `nvdec` context-stability issue after a GPU
///    power-state transition during a long idle period.
///  - `hwdec-current` / `current-vo` — kept from the last round; already
///    confirmed `nvdec` / `libmpv` (the render-API embedding path) on this
///    setup, kept here for continuity across future runs/platforms.
///
/// Still makes no playback decisions and never mutates player state.
class PlaybackDiagnostics {
  final Player player;

  PlaybackDiagnostics({required this.player}) {
    _playingSub = player.stream.playing.listen(_onPlayingChanged);
    _positionSub = player.stream.position.listen(_onPositionChanged);
  }

  static const Duration _pollInterval = Duration(seconds: 15);

  // ── A jump larger than this between two consecutive position-stream
  // ticks is treated as a seek (scrub, skip-chip, chapter-jump shortcut)
  // rather than ordinary forward playback progress — normal ticks move by
  // well under a second. ──
  static const Duration _seekJumpThreshold = Duration(seconds: 2);

  static const _tag = 'PlaybackDiagnostics';

  Timer? _pollTimer;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<Duration> _positionSub;
  Duration? _lastPosition;
  bool _disposed = false;

  void _onPlayingChanged(bool playing) {
    if (playing) {
      _pollTimer?.cancel();
      _pollTimer = null;
      // ── Resume: log immediately, then at +2s and +5s — the further-out
      // checkpoints exist specifically to see whether
      // estimated-frame-number is STILL climbing well past the point a
      // human would already perceive the picture as frozen, which is the
      // key signal for distinguishing "mpv's decode pipeline stalled" from
      // "mpv is fine, Flutter just isn't displaying what it's handed." ──
      unawaited(_logSnapshot('resume'));
      unawaited(
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed) unawaited(_logSnapshot('resume+2s'));
        }),
      );
      unawaited(
        Future.delayed(const Duration(seconds: 5), () {
          if (!_disposed) unawaited(_logSnapshot('resume+5s'));
        }),
      );
    } else {
      unawaited(_logSnapshot('pause'));
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        unawaited(_logSnapshot('paused-poll'));
      });
    }
  }

  void _onPositionChanged(Duration pos) {
    final last = _lastPosition;
    _lastPosition = pos;
    if (last == null) return;

    if ((pos - last).abs() > _seekJumpThreshold) {
      unawaited(_logSnapshot('seek'));
      unawaited(
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed) unawaited(_logSnapshot('seek+2s'));
        }),
      );
    }
  }

  Future<void> _logSnapshot(String label) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    Future<String> read(String name) async {
      try {
        return await platform.getProperty(name);
      } catch (e) {
        return '<error: $e>';
      }
    }

    final position = player.state.position;

    // ── Cache/demuxer layer — already confirmed healthy through every
    // reproduction so far, kept for continuity/comparison. ──
    final coreIdle = await read('core-idle');
    final demuxerCacheIdle = await read('demuxer-cache-idle');
    final pausedForCache = await read('paused-for-cache');
    final cacheBufferingState = await read('cache-buffering-state');
    final demuxerCacheTime = await read('demuxer-cache-time');
    final eofReached = await read('eof-reached');

    // ── Frame/output layer. estimated-frame-number (NOT
    // estimated-frame-count — see class doc for why that was wrong) is
    // the actual live decode-progress signal this round is built around. ──
    final estimatedFrameNumber = await read('estimated-frame-number');
    final frameDropCount = await read('frame-drop-count');
    final decoderFrameDropCount = await read('decoder-frame-drop-count');
    final hwdecCurrent = await read('hwdec-current');
    final currentVo = await read('current-vo');

    AppLogger.i(
      _tag,
      '[$label] pos=$position core-idle=$coreIdle '
      'demuxer-cache-idle=$demuxerCacheIdle paused-for-cache=$pausedForCache '
      'cache-buffering-state=$cacheBufferingState% '
      'demuxer-cache-time=${demuxerCacheTime}s eof-reached=$eofReached '
      '|| estimated-frame-number=$estimatedFrameNumber '
      'frame-drop-count=$frameDropCount '
      'decoder-frame-drop-count=$decoderFrameDropCount '
      'hwdec-current=$hwdecCurrent current-vo=$currentVo',
    );
  }

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    unawaited(_playingSub.cancel());
    unawaited(_positionSub.cancel());
  }
}
