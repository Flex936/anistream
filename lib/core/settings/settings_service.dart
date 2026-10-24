import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;
  final String androidHwDec;

  /// When true, tapping an episode skips `TorrentSearchModal` and streams the
  /// top-scored torrent, falling back to the modal on no results or a failed
  /// search (`AnimeDetailsScreen._autoSelectTopTorrentAndStream`). Governs
  /// torrent selection only; [episodeAutoplayEnabled] governs
  /// episode-to-episode advancement.
  final bool autoTorrentEnabled;

  /// When true, finishing an episode (or the Next Episode chip) streams the
  /// next one instead of returning to `AnimeDetailsScreen`. Independent of
  /// [autoTorrentEnabled] — hands-off advancement and auto-selection are
  /// separate choices.
  final bool episodeAutoplayEnabled;

  final bool autoSkip;

  final bool showFreezeRecoveryButton;

  final bool uiPerformanceMode;
  final String videoFilterQuality;

  final bool serverMode;

  /// Base URL of the AniStream Go server, e.g. "http://192.168.1.5:7878".
  final String serverUrl;

  /// When true (mobile/TV only — see [SettingsMenu]'s platform gate), episode
  /// playback goes through [ExoTheaterScreen] instead of the default
  /// [TheaterScreen]. Independent of [uiPerformanceMode], which is scoped to UI
  /// chrome, not the decode/render engine.
  final bool useExoPlayer;

  /// Whether libass subtitle rendering is on for the next `Player` this setting
  /// drives (ARCHITECTURE.md § 5), defaulting to `true`. Surfaced only through
  /// `TheaterSettingsMenu`; meaningless outside a session, and
  /// `ExoTheaterScreen` ignores it.
  final bool libassEnabled;

  const AppSettings({
    this.filterEcchi = true,
    this.hardwareDecoding = 'auto',
    this.androidHwDec = 'mediacodec-copy',
    this.autoTorrentEnabled = false,
    this.episodeAutoplayEnabled = false,
    this.autoSkip = false,
    this.showFreezeRecoveryButton = false,
    this.uiPerformanceMode = false,
    this.videoFilterQuality = 'low',
    this.serverMode = false,
    this.serverUrl = 'http://192.168.1.100:7878',
    this.useExoPlayer = false,
    this.libassEnabled = true,
  });
}

/// Synchronous, in-memory mirror of [AppSettings] for services with no
/// [BuildContext] (`AnilistQueryService`, instantiated fresh per screen) — see
/// ARCHITECTURE.md § 3 for what it fixes and why. [SettingsController] is its
/// only writer.
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
  static const String kAutoTorrentEnabled = 'auto_torrent_enabled';
  static const String kEpisodeAutoplayEnabled = 'episode_autoplay_enabled';
  static const String kAutoSkip = 'auto_skip';
  static const String kShowFreezeRecoveryButton = 'show_freeze_recovery_button';
  static const String kUiPerformanceMode = 'ui_performance_mode';
  static const String kVideoFilterQuality = 'video_filter_quality';
  static const String kServerMode = 'server_mode';
  static const String kServerUrl = 'server_url';
  static const String kuseExoPlayer = 'use_exo_player';
  static const String kLibassEnabled = 'libass_enabled';

  /// Persisted key name [kAutoTorrentEnabled] used before the
  /// autoplay/autotorrent rename. Kept only so the two migration methods
  /// below have a stable name to reference — never read or written
  /// anywhere else.
  static const String _kLegacyAutoTorrentKey = 'autoplay_enabled';

  /// One-time guard so the legacy → async migration below runs at most once
  /// per install, not on every cold start.
  static const String _kMigrationDoneKey = 'settings_migrated_to_async_v1';

  /// One-time guard for the autoplay/autotorrent rename migration —
  /// deliberately a *different* key than [_kMigrationDoneKey] above.
  static const String _kAutoTorrentRenameMigrationDoneKey =
      'settings_migrated_autotorrent_rename_v1';

  final SharedPreferencesAsync _prefs;

  SettingsService({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  Future<AppSettings> load() async {
    await _migrateLegacyPrefsIfNeeded();
    await _migrateAutoTorrentRenameIfNeeded();

    return AppSettings(
      filterEcchi: await _prefs.getBool(kFilterEcchi) ?? true,
      hardwareDecoding: await _prefs.getString(kHwDec) ?? 'auto',
      androidHwDec: await _prefs.getString(kAndroidHwDec) ?? 'mediacodec-copy',
      autoTorrentEnabled: await _prefs.getBool(kAutoTorrentEnabled) ?? false,
      episodeAutoplayEnabled:
          await _prefs.getBool(kEpisodeAutoplayEnabled) ?? false,
      autoSkip: await _prefs.getBool(kAutoSkip) ?? false,
      showFreezeRecoveryButton:
          await _prefs.getBool(kShowFreezeRecoveryButton) ?? false,
      uiPerformanceMode: await _prefs.getBool(kUiPerformanceMode) ?? false,
      videoFilterQuality: await _prefs.getString(kVideoFilterQuality) ?? 'low',
      serverMode: await _prefs.getBool(kServerMode) ?? false,
      serverUrl:
          await _prefs.getString(kServerUrl) ?? 'http://192.168.1.100:7878',
      useExoPlayer: await _prefs.getBool(kuseExoPlayer) ?? false,
      libassEnabled: await _prefs.getBool(kLibassEnabled) ?? true,
    );
  }

  Future<void> save(AppSettings settings) async {
    await Future.wait([
      _prefs.setBool(kFilterEcchi, settings.filterEcchi),
      _prefs.setString(kHwDec, settings.hardwareDecoding),
      _prefs.setString(kAndroidHwDec, settings.androidHwDec),
      _prefs.setBool(kAutoTorrentEnabled, settings.autoTorrentEnabled),
      _prefs.setBool(kEpisodeAutoplayEnabled, settings.episodeAutoplayEnabled),
      _prefs.setBool(kAutoSkip, settings.autoSkip),
      _prefs.setBool(
        kShowFreezeRecoveryButton,
        settings.showFreezeRecoveryButton,
      ),
      _prefs.setBool(kUiPerformanceMode, settings.uiPerformanceMode),
      _prefs.setString(kVideoFilterQuality, settings.videoFilterQuality),
      _prefs.setBool(kServerMode, settings.serverMode),
      _prefs.setString(kServerUrl, settings.serverUrl),
      _prefs.setBool(kuseExoPlayer, settings.useExoPlayer),
      _prefs.setBool(kLibassEnabled, settings.libassEnabled),
    ]);
  }

  /// Copies any values a previous build wrote via the legacy
  /// `SharedPreferences.getInstance()` API into the async store this class now
  /// reads and writes exclusively.
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
        migrateBool(_kLegacyAutoTorrentKey),
        migrateBool(kAutoSkip),
        migrateBool(kShowFreezeRecoveryButton),
        migrateBool(kUiPerformanceMode),
        migrateString(kVideoFilterQuality),
        migrateBool(kServerMode),
        migrateString(kServerUrl),
      ]);
    } catch (_) {
      // Fresh install / no legacy plugin data / platform quirk.
    } finally {
      await _prefs.setBool(_kMigrationDoneKey, true);
    }
  }

  /// Copies a pre-rename [_kLegacyAutoTorrentKey] value into
  /// [kAutoTorrentEnabled], its new name. [AppSettings.episodeAutoplayEnabled]
  /// is a genuinely new feature and is deliberately NOT seeded from this
  /// value — it always starts at its own default.
  Future<void> _migrateAutoTorrentRenameIfNeeded() async {
    final alreadyMigrated =
        await _prefs.getBool(_kAutoTorrentRenameMigrationDoneKey) ?? false;
    if (alreadyMigrated) return;

    try {
      final oldValue = await _prefs.getBool(_kLegacyAutoTorrentKey);
      if (oldValue != null) {
        await _prefs.setBool(kAutoTorrentEnabled, oldValue);
      }
    } finally {
      await _prefs.setBool(_kAutoTorrentRenameMigrationDoneKey, true);
    }
  }
}