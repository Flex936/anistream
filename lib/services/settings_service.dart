import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;
  final bool autoPlayRecommended;

  const AppSettings({
    required this.filterEcchi,
    required this.hardwareDecoding,
    required this.autoPlayRecommended,
  });

  factory AppSettings.defaults() => const AppSettings(
        filterEcchi: true,
        hardwareDecoding: 'auto',
        autoPlayRecommended: false,
      );
}

class SettingsService {
  static const kFilterEcchi = 'filter_ecchi';
  static const kHwDec = 'hwdec_preference';
  static const kAutoPlay = 'auto_play_recommended';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      filterEcchi: prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: prefs.getString(kHwDec) ?? 'auto',
      autoPlayRecommended: prefs.getBool(kAutoPlay) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(kFilterEcchi, settings.filterEcchi),
      prefs.setString(kHwDec, settings.hardwareDecoding),
      prefs.setBool(kAutoPlay, settings.autoPlayRecommended),
    ]);
  }
}