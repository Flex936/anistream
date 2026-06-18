import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;

  const AppSettings({
    required this.filterEcchi,
    required this.hardwareDecoding,
  });

  factory AppSettings.defaults() => const AppSettings(
        filterEcchi: true,
        hardwareDecoding: 'auto',
      );
}

class SettingsService {
  static const kFilterEcchi = 'filter_ecchi';
  static const kHwDec = 'hwdec_preference';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      filterEcchi: prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: prefs.getString(kHwDec) ?? 'auto',
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(kFilterEcchi, settings.filterEcchi),
      prefs.setString(kHwDec, settings.hardwareDecoding),
    ]);
  }
}