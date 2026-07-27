import 'dart:async';
import 'dart:io' show Platform;

import 'package:media_kit/media_kit.dart';

import '../../../core/settings/settings_service.dart';

/// Shared mpv property configuration for the theater window — respects the
/// user's saved hardware-decoding preference per platform.
abstract final class PlayerConfigurator {
  /// `Future<void>`-returning (not `void`) and `await`ed by callers.
  /// `NativePlayer.setProperty` itself returns `Future<void>` — firing six
  /// of them off unawaited per playback session was six separate
  /// `unawaited_futures` violations. Callers now `await` this.
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
    await _applyStreamingTuning(platform);
  }

  static Future<void> _applyStreamingTuning(NativePlayer platform) async {
    await platform.setProperty('cache', 'yes');
    await platform.setProperty('demuxer-max-bytes', '150000000');
    await platform.setProperty('demuxer-readahead-secs', '120');
  }
}
