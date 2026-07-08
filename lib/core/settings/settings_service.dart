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

/// Synchronous, in-memory snapshot of the current [AppSettings].
///
/// Services with no [BuildContext] — [AnilistQueryService] is instantiated
/// fresh in `HomeScreen`, `SearchResultsScreen`, `WatchlistController`,
/// `ScheduledScreen`, etc., none of which have an ambient widget tree to
/// walk up to [SettingsScope] — previously worked around this by re-reading
/// `shared_preferences` directly on every call. That direct read is what
/// caused the "Filter Ecchi" bug: it went through `SharedPreferencesAsync`,
/// a *different* underlying native store than [SettingsService] wrote
/// through (`SharedPreferences.getInstance()`, the legacy singleton API).
/// As of shared_preferences 2.3+, those two APIs are not guaranteed to
/// share a backend — the setting looked saved, but nothing that read it
/// through the other API ever saw the new value.
///
/// [SettingsCache] fixes this at the root: [SettingsController] is the only
/// writer (on both [SettingsController.reload] and [SettingsController.update]),
/// so any non-widget service reads the exact same in-memory value a widget
/// under [SettingsScope] would — no second disk round-trip, no second store
/// to silently drift out of sync with the first.
abstract final class SettingsCache {
  static AppSettings _current = const AppSettings();
  static AppSettings get current => _current;

  static void update(AppSettings settings) {
    _current = settings;
  }
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

  /// One-time guard so the legacy → async migration below runs at most once
  /// per install, not on every cold start.
  static const String _kMigrationDoneKey = 'settings_migrated_to_async_v1';

  // ── Every read/write in this service now goes through the SAME
  // shared_preferences API the rest of the app already standardized on
  // (AnilistAuthService's token, TheaterControls' saved volume). Mixing the
  // legacy singleton API with this new one was the actual bug — see
  // SettingsCache's doc comment above. ──
  final SharedPreferencesAsync _prefs;

  SettingsService({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  Future<AppSettings> load() async {
    await _migrateLegacyPrefsIfNeeded();

    return AppSettings(
      filterEcchi: await _prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: await _prefs.getString(kHwDec) ?? 'auto',
      androidHwDec: await _prefs.getString(kAndroidHwDec) ?? 'mediacodec-copy',
      autoPlayEnabled: await _prefs.getBool(kAutoPlayEnabled) ?? false,
      autoSkip: await _prefs.getBool(kAutoSkip) ?? false,
      uiPerformanceMode: await _prefs.getBool(kUiPerformanceMode) ?? false,
      videoFilterQuality: await _prefs.getString(kVideoFilterQuality) ?? 'low',
      serverMode: await _prefs.getBool(kServerMode) ?? false,
      serverUrl:
          await _prefs.getString(kServerUrl) ?? 'http://192.168.1.100:7878',
    );
  }

  Future<void> save(AppSettings settings) async {
    // ── Fired concurrently — these are independent keys, so there's no
    // ordering dependency between them, and the settings menu shouldn't
    // block on 9 sequential awaits just to close the dialog. ──
    await Future.wait([
      _prefs.setBool(kFilterEcchi, settings.filterEcchi),
      _prefs.setString(kHwDec, settings.hardwareDecoding),
      _prefs.setString(kAndroidHwDec, settings.androidHwDec),
      _prefs.setBool(kAutoPlayEnabled, settings.autoPlayEnabled),
      _prefs.setBool(kAutoSkip, settings.autoSkip),
      _prefs.setBool(kUiPerformanceMode, settings.uiPerformanceMode),
      _prefs.setString(kVideoFilterQuality, settings.videoFilterQuality),
      _prefs.setBool(kServerMode, settings.serverMode),
      _prefs.setString(kServerUrl, settings.serverUrl),
    ]);
  }

  /// Copies any values a previous build wrote via the legacy
  /// `SharedPreferences.getInstance()` API into the async store this class
  /// now reads/writes exclusively, so upgrading users don't silently lose
  /// settings they'd already configured (Filter Ecchi being the one that
  /// actually mattered, since it's the only key another service also read
  /// independently — but every key is migrated for safety).
  Future<void> _migrateLegacyPrefsIfNeeded() async {
    final alreadyMigrated = await _prefs.getBool(_kMigrationDoneKey) ?? false;
    if (alreadyMigrated) return;

    try {
      final legacy = await SharedPreferences.getInstance();

      Future<void> migrateBool(String key) async {
        if (legacy.containsKey(key)) {
          final value = legacy.getBool(key);
          if (value != null) await _prefs.setBool(key, value);
        }
      }

      Future<void> migrateString(String key) async {
        if (legacy.containsKey(key)) {
          final value = legacy.getString(key);
          if (value != null) await _prefs.setString(key, value);
        }
      }

      await Future.wait([
        migrateBool(kFilterEcchi),
        migrateString(kHwDec),
        migrateString(kAndroidHwDec),
        migrateBool(kAutoPlayEnabled),
        migrateBool(kAutoSkip),
        migrateBool(kUiPerformanceMode),
        migrateString(kVideoFilterQuality),
        migrateBool(kServerMode),
        migrateString(kServerUrl),
      ]);
    } catch (_) {
      // Fresh install / no legacy plugin data / platform quirk — nothing
      // to carry over. Not fatal either way.
    } finally {
      await _prefs.setBool(_kMigrationDoneKey, true);
    }
  }
}
