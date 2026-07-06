import 'dart:io' show Platform;
import 'package:media_kit/media_kit.dart';
import '../../../core/settings/settings_service.dart';

/// Shared mpv property configuration for both the main theater window and
/// the detached PIP window — previously duplicated between
/// `TheaterScreen._initPlayerAndStream` and `PipPlayerWindow._configurePlayer`.
abstract final class PlayerConfigurator {
  /// Full path for the main theater window — respects the user's saved
  /// hardware-decoding preference per platform.
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

  /// Simplified path for the detached PIP window (desktop-only, always
  /// safe-mode hwdec, no per-platform branching).
  static void configureForPip(Player player) {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    platform.setProperty('hwdec', 'auto-safe');
    _applyStreamingTuning(platform);
  }

  static void _applyStreamingTuning(NativePlayer platform) {
    platform.setProperty('cache', 'yes');
    platform.setProperty('demuxer-max-bytes', '150000000');
    platform.setProperty('demuxer-readahead-secs', '120');
  }
}
