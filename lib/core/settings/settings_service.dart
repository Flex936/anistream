import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;
  final String androidHwDec;
  final bool autoPlayEnabled;
  final bool autoSkip;

  // ── INDEPENDENT SETTINGS ──
  final bool uiPerformanceMode;
  final String videoFilterQuality;

  const AppSettings({
    this.filterEcchi = true,
    this.hardwareDecoding = 'auto',
    this.androidHwDec = 'mediacodec-copy',
    this.autoPlayEnabled = false,
    this.autoSkip = false,
    this.uiPerformanceMode = false,
    this.videoFilterQuality = 'low', // Default
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

  // ── Instantiate the modern async API once ──
  final _prefs = SharedPreferencesAsync();

  Future<AppSettings> load() async {
    // ── Await each individual read from the async disk store ──
    return AppSettings(
      filterEcchi: await _prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: await _prefs.getString(kHwDec) ?? 'auto',
      androidHwDec: await _prefs.getString(kAndroidHwDec) ?? 'mediacodec-copy',
      autoPlayEnabled: await _prefs.getBool(kAutoPlayEnabled) ?? false,
      autoSkip: await _prefs.getBool(kAutoSkip) ?? false,
      uiPerformanceMode: await _prefs.getBool(kUiPerformanceMode) ?? false,
      videoFilterQuality: await _prefs.getString(kVideoFilterQuality) ?? 'low',
    );
  }

  Future<void> save(AppSettings settings) async {
    // ── Fire-and-forget or await individual background writes ──
    await _prefs.setBool(kFilterEcchi, settings.filterEcchi);
    await _prefs.setString(kHwDec, settings.hardwareDecoding);
    await _prefs.setString(kAndroidHwDec, settings.androidHwDec);
    await _prefs.setBool(kAutoPlayEnabled, settings.autoPlayEnabled);
    await _prefs.setBool(kAutoSkip, settings.autoSkip);
    await _prefs.setBool(kUiPerformanceMode, settings.uiPerformanceMode);
    await _prefs.setString(kVideoFilterQuality, settings.videoFilterQuality);
  }
}
