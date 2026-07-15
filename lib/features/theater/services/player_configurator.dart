import 'dart:io' show Platform;
import 'package:media_kit/media_kit.dart';
import '../../../core/settings/settings_service.dart';

/// Shared mpv property configuration for the theater window — respects the
/// user's saved hardware-decoding preference per platform.
abstract final class PlayerConfigurator {
  static void configureForTheater(Player player, AppSettings settings) {
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    final hwdec = settings.hardwareDecoding;
    if (hwdec == 'auto') {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        platform.setProperty('hwdec', 'auto-safe');
      } else if (Platform.isAndroid) {
        platform.setProperty('hwdec', settings.androidHwDec);
      } else if (Platform.isIOS) {
        platform.setProperty('hwdec', 'videotoolbox');
      }
    } else if (hwdec != 'none') {
      platform.setProperty('hwdec', hwdec);
    }
    _applyStreamingTuning(platform);
  }

  static void _applyStreamingTuning(NativePlayer platform) {
    platform.setProperty('cache', 'yes');
    platform.setProperty('demuxer-max-bytes', '150000000');
    platform.setProperty('demuxer-readahead-secs', '120');
  }
}
