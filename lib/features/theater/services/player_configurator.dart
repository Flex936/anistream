import 'dart:async';
import 'dart:io' show Platform;

import 'package:media_kit/media_kit.dart';

import '../../../core/settings/settings_service.dart';

/// Shared mpv setup for the theater window: per-platform hwdec, and smaller
/// demuxer and decode-thread limits under `uiPerformanceMode` (DESIGN.md § 2).
abstract final class PlayerConfigurator {
  /// Awaited by callers: each property set must complete before the next.
  static Future<void> configureForTheater(
    Player player,
    AppSettings settings,
  ) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    final hwdec = settings.hardwareDecoding;
    if (hwdec == 'auto') {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await platform.setProperty('hwdec', 'auto-safe');
      } else if (Platform.isAndroid) {
        await platform.setProperty('hwdec', settings.androidHwDec);
      } else if (Platform.isIOS) {
        await platform.setProperty('hwdec', 'videotoolbox');
      }
    } else if (hwdec != 'none') {
      await platform.setProperty('hwdec', hwdec);
    }
    await _applyStreamingTuning(platform, settings.uiPerformanceMode);
  }

  static Future<void> _applyStreamingTuning(
    NativePlayer platform,
    bool uiPerformanceMode,
  ) async {
    await platform.setProperty('cache', 'yes');

    // Smaller under uiPerformanceMode, yet still well ahead of a sequentially
    // downloaded stream.
    await platform.setProperty(
      'demuxer-max-bytes',
      uiPerformanceMode ? '70000000' : '150000000',
    );
    await platform.setProperty(
      'demuxer-readahead-secs',
      uiPerformanceMode ? '45' : '120',
    );

    // Software-decode fallback only (hwdec never reads this); caps threads so a
    // weak TV SoC doesn't compete with the UI isolate.
    if (uiPerformanceMode) {
      await platform.setProperty('vd-lavc-threads', '2');
    }

    // See ARCHITECTURE.md § 5.
    await platform.setProperty('network-timeout', '10');
    await platform.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
    );
  }
}
