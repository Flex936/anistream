import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;
  final String androidHwDec;
  final bool autoPlayEnabled;
  final bool autoSkip;

  // ── PERFORMANCE ──
  final bool uiPerformanceMode;
  final String videoFilterQuality;

  // ── REMOTE SERVER ──
  /// When true, [TheaterScreen] uses [RemoteStreamingController] instead of
  /// the on-device libtorrent engine.
  final bool serverMode;

  /// Base URL of the AniStream Go server, e.g. "http://192.168.1.5:7878".
  final String serverUrl;

  const AppSettings({
    this.filterEcchi = true,
    this.hardwareDecoding = 'auto',
    this.androidHwDec = 'mediacodec-copy',
    this.autoPlayEnabled = false,
    this.autoSkip = false,
    this.uiPerformanceMode = false,
    this.videoFilterQuality = 'low',
    this.serverMode = false,
    this.serverUrl = 'http://192.168.1.100:7878',
  });
}

class SettingsService {
  static const String kFilterEcchi = 'filter_ecchi';
  static const String kHwDec = 'hwdec';
  static const String kAndroidHwDec = 'android_hwdec';
  static const String kAutoPlayEnabled = 'autoplay_enabled';
  static const String kAutoSkip = 'auto_skip';
  static const String kUiPerformanceMode = 'ui_performance_mode';
  static const String kVideoFilterQuality = 'video_filter_quality';
  static const String kServerMode = 'server_mode';
  static const String kServerUrl = 'server_url';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      filterEcchi: prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: prefs.getString(kHwDec) ?? 'auto',
      androidHwDec: prefs.getString(kAndroidHwDec) ?? 'mediacodec-copy',
      autoPlayEnabled: prefs.getBool(kAutoPlayEnabled) ?? false,
      autoSkip: prefs.getBool(kAutoSkip) ?? false,
      uiPerformanceMode: prefs.getBool(kUiPerformanceMode) ?? false,
      videoFilterQuality: prefs.getString(kVideoFilterQuality) ?? 'low',
      serverMode: prefs.getBool(kServerMode) ?? false,
      serverUrl: prefs.getString(kServerUrl) ?? 'http://192.168.1.100:7878',
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kFilterEcchi, settings.filterEcchi);
    await prefs.setString(kHwDec, settings.hardwareDecoding);
    await prefs.setString(kAndroidHwDec, settings.androidHwDec);
    await prefs.setBool(kAutoPlayEnabled, settings.autoPlayEnabled);
    await prefs.setBool(kAutoSkip, settings.autoSkip);
    await prefs.setBool(kUiPerformanceMode, settings.uiPerformanceMode);
    await prefs.setString(kVideoFilterQuality, settings.videoFilterQuality);
    await prefs.setBool(kServerMode, settings.serverMode);
    await prefs.setString(kServerUrl, settings.serverUrl);
  }
}
