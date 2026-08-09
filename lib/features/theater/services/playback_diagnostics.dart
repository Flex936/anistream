import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../../core/logging/app_logger.dart';

/// Read-only diagnostic instrumentation for an mpv permanent-freeze bug
/// reported after ~5-10 minutes of paused playback, where scrubbing
/// afterward fails to resume frame rendering.
///
/// This class makes no playback decisions and never mutates player
/// state — it only logs mpv's own cache/idle properties via [AppLogger],
/// on a timer while paused and immediately around resume/seek, so the
/// working hypothesis behind [PlayerConfigurator]'s reconnect tuning (a
/// long pause outlives the underlying HTTP connection's keep-alive
/// window — either the local loopback server's own idle handling for
/// [StreamingController], or an intermediate NAT/router on the LAN path
/// for [RemoteStreamingController] — and mpv's demuxer has no built-in
/// awareness the socket died, so it never proactively reissues the
/// ranged GET on resume) can be checked against real device logs rather
/// than asserted from symptoms alone.
///
/// See [AppLogger.logsDirectoryPath] for where these lines end up on
/// disk. These logs are what distinguish two very different root causes:
/// whether `demuxer-cache-idle`/`core-idle` are already `yes` well before
/// the freeze is externally observed (pointing at a genuinely dead
/// connection mpv itself gave up retrying) versus `no` (pointing
/// elsewhere entirely — a UI-thread issue, not an mpv/network one).
///
/// Deliberately only active while genuinely paused — polling mpv
/// properties every second during normal playback would be wasted IPC
/// chatter for a bug that, per the report, only manifests after an
/// extended pause.
class PlaybackDiagnostics {
  final Player player;

  PlaybackDiagnostics({required this.player}) {
    _playingSub = player.stream.playing.listen(_onPlayingChanged);
    _positionSub = player.stream.position.listen(_onPositionChanged);
  }

  static const Duration _pollInterval = Duration(seconds: 15);

  // A jump larger than this between two consecutive position-stream
  // ticks is treated as a seek (scrub, skip-chip, chapter-jump shortcut)
  // rather than ordinary forward playback progress — normal ticks move
  // by well under a second.
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
      // Resume: logs immediately, then again after a short delay so the
      // pair of lines shows whether position is actually advancing or
      // the freeze reproduces on this specific resume.
      unawaited(_logSnapshot('resume'));
      unawaited(
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed) unawaited(_logSnapshot('resume+2s'));
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
    final coreIdle = await read('core-idle');
    final demuxerCacheIdle = await read('demuxer-cache-idle');
    final pausedForCache = await read('paused-for-cache');
    final cacheBufferingState = await read('cache-buffering-state');
    final demuxerCacheTime = await read('demuxer-cache-time');
    final eofReached = await read('eof-reached');

    AppLogger.i(
      _tag,
      '[$label] pos=$position core-idle=$coreIdle '
      'demuxer-cache-idle=$demuxerCacheIdle paused-for-cache=$pausedForCache '
      'cache-buffering-state=$cacheBufferingState% '
      'demuxer-cache-time=${demuxerCacheTime}s eof-reached=$eofReached',
    );
  }

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    unawaited(_playingSub.cancel());
    unawaited(_positionSub.cancel());
  }
}
