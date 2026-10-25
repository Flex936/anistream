import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../../core/logging/app_logger.dart';

/// Read-only mpv logger for the pause-freeze: logs cache and idle properties
/// while paused and around resume and seek. See ARCHITECTURE.md § 5.
class PlaybackDiagnostics {
  final Player player;

  PlaybackDiagnostics({required this.player}) {
    _playingSub = player.stream.playing.listen(_onPlayingChanged);
    _positionSub = player.stream.position.listen(_onPositionChanged);
  }

  static const Duration _pollInterval = Duration(seconds: 15);

  // A position jump above this between ticks counts as a seek.
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
      // Logs immediately and again after 2s, showing whether position advances.
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
