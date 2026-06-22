import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;
  final String androidHwDec;
  final bool autoPlayEnabled;
  final bool autoSkip;

  const AppSettings({
    this.filterEcchi = true,
    this.hardwareDecoding = 'auto',
    this.androidHwDec = 'mediacodec-copy',
    this.autoPlayEnabled = false,
    this.autoSkip = false,
  });
}

class SettingsService {
  static const String kFilterEcchi = 'filter_ecchi';
  static const String kHwDec = 'hwdec';
  static const String kAndroidHwDec = 'android_hwdec';
  static const String kAutoPlayEnabled = 'autoplay_enabled';
  static const String kAutoSkip = 'auto_skip';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      filterEcchi: prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: prefs.getString(kHwDec) ?? 'auto',
      androidHwDec: prefs.getString(kAndroidHwDec) ?? 'mediacodec-copy',
      autoPlayEnabled: prefs.getBool(kAutoPlayEnabled) ?? false,
      autoSkip: prefs.getBool(kAutoSkip) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kFilterEcchi, settings.filterEcchi);
    await prefs.setString(kHwDec, settings.hardwareDecoding);
    await prefs.setString(kAndroidHwDec, settings.androidHwDec);
    await prefs.setBool(kAutoPlayEnabled, settings.autoPlayEnabled);
    await prefs.setBool(kAutoSkip, settings.autoSkip);
  }
}
