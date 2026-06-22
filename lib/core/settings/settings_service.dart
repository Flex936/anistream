import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;
  final bool autoPlayRecommended;
  final bool autoSkip;

  const AppSettings({
    required this.filterEcchi,
    required this.hardwareDecoding,
    required this.autoPlayRecommended,
    required this.autoSkip,
  });

  factory AppSettings.defaults() => const AppSettings(
    filterEcchi: true,
    hardwareDecoding: 'auto',
    autoPlayRecommended: false,
    autoSkip: false,
  );
}

class SettingsService {
  static const kFilterEcchi = 'filter_ecchi';
  static const kHwDec = 'hwdec_preference';
  static const kAutoPlay = 'auto_play_recommended';
  static const kAutoSkip = 'auto_skip_op_ed';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      filterEcchi: prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: prefs.getString(kHwDec) ?? 'auto',
      autoPlayRecommended: prefs.getBool(kAutoPlay) ?? false,
      autoSkip: prefs.getBool(kAutoSkip) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(kFilterEcchi, settings.filterEcchi),
      prefs.setString(kHwDec, settings.hardwareDecoding),
      prefs.setBool(kAutoPlay, settings.autoPlayRecommended),
      prefs.setBool(kAutoSkip, settings.autoSkip),
    ]);
  }
}
