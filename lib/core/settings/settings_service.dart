import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool filterEcchi;
  final String hardwareDecoding;
  final String androidHwDec;
  final bool autoPlayEnabled;
  final bool autoSkip;

  /// Gates a manual "restart player" button shown in the theater top bar
  /// — a recovery action for a confirmed Linux/NVIDIA/Wayland video-freeze
  /// bug in media_kit_video's texture delivery after a long pause, where
  /// full player recreation is the only recovery (see ARCHITECTURE.md
  /// § 7 for the diagnostic trail, including two automatic mitigations
  /// that were tried and confirmed ineffective before landing here).
  /// Defaults to `false`: the bug is confirmed on that one platform
  /// combination only, and the button is a deliberate, user-triggered
  /// action rather than anything automatic, since no mpv property
  /// distinguishes a frozen frame from a healthy one.
  final bool showFreezeRecoveryButton;

  // ── PERFORMANCE ──
  final bool uiPerformanceMode;
  final String videoFilterQuality;

  // ── REMOTE SERVER ──
  /// When true, [TheaterScreen] uses [RemoteStreamingController] instead of
  /// the on-device libtorrent engine.
  final bool serverMode;

  /// Base URL of the AniStream Go server, e.g. "http://192.168.1.5:7878".
  final String serverUrl;

  /// Whether libass-based subtitle rendering is enabled for the next
  /// `Player` this setting drives. `media_kit`'s `PlayerConfiguration.
  /// libass` is only ever read when a `Player` is constructed — there's
  /// no exposed way to flip it on an already-running instance — so
  /// `TheaterScreen` reads this once at construction time via
  /// `SettingsScope`, and a mid-session change goes through a full
  /// player restart-and-resume instead of a live property flip; see
  /// `TheaterScreen._handleLibassToggle`. Surfaced exclusively through
  /// `TheaterSettingsMenu`, not this app's main Settings drawer, since
  /// it's only meaningful while actively watching something. Defaults to
  /// `true`, matching this app's behavior before this setting existed.
  final bool libassEnabled;

  const AppSettings({
    this.filterEcchi = true,
    this.hardwareDecoding = 'auto',
    this.androidHwDec = 'mediacodec-copy',
    this.autoPlayEnabled = false,
    this.autoSkip = false,
    this.showFreezeRecoveryButton = false,
    this.uiPerformanceMode = false,
    this.videoFilterQuality = 'low',
    this.serverMode = false,
    this.serverUrl = 'http://192.168.1.100:7878',
    this.libassEnabled = true,
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
  static const String kShowFreezeRecoveryButton = 'show_freeze_recovery_button';
  static const String kUiPerformanceMode = 'ui_performance_mode';
  static const String kVideoFilterQuality = 'video_filter_quality';
  static const String kServerMode = 'server_mode';
  static const String kServerUrl = 'server_url';
  static const String kLibassEnabled = 'libass_enabled';

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
      showFreezeRecoveryButton:
          await _prefs.getBool(kShowFreezeRecoveryButton) ?? false,
      uiPerformanceMode: await _prefs.getBool(kUiPerformanceMode) ?? false,
      videoFilterQuality: await _prefs.getString(kVideoFilterQuality) ?? 'low',
      serverMode: await _prefs.getBool(kServerMode) ?? false,
      serverUrl:
          await _prefs.getString(kServerUrl) ?? 'http://192.168.1.100:7878',
      libassEnabled: await _prefs.getBool(kLibassEnabled) ?? true,
    );
  }

  Future<void> save(AppSettings settings) async {
    // ── Fired concurrently — these are independent keys, so there's no
    // ordering dependency between them, and the settings menu shouldn't
    // block on 10 sequential awaits just to close the dialog. ──
    await Future.wait([
      _prefs.setBool(kFilterEcchi, settings.filterEcchi),
      _prefs.setString(kHwDec, settings.hardwareDecoding),
      _prefs.setString(kAndroidHwDec, settings.androidHwDec),
      _prefs.setBool(kAutoPlayEnabled, settings.autoPlayEnabled),
      _prefs.setBool(kAutoSkip, settings.autoSkip),
      _prefs.setBool(
        kShowFreezeRecoveryButton,
        settings.showFreezeRecoveryButton,
      ),
      _prefs.setBool(kUiPerformanceMode, settings.uiPerformanceMode),
      _prefs.setString(kVideoFilterQuality, settings.videoFilterQuality),
      _prefs.setBool(kServerMode, settings.serverMode),
      _prefs.setString(kServerUrl, settings.serverUrl),
      _prefs.setBool(kLibassEnabled, settings.libassEnabled),
    ]);
  }

  /// Copies any values a previous build wrote via the legacy
  /// `SharedPreferences.getInstance()` API into the async store this class
  /// now reads/writes exclusively, so upgrading users don't silently lose
  /// settings they'd already configured (Filter Ecchi being the one that
  /// actually mattered, since it's the only key another service also read
  /// independently — but every key is migrated for safety). `libassEnabled`
  /// never existed under the legacy API either way — its migration call is
  /// a permanent no-op — but it's included for the same "every key goes
  /// through the same path" consistency the rest of this list already
  /// follows, rather than being silently special-cased out.
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
        migrateBool(kShowFreezeRecoveryButton),
        migrateBool(kUiPerformanceMode),
        migrateString(kVideoFilterQuality),
        migrateBool(kServerMode),
        migrateString(kServerUrl),
        migrateBool(kLibassEnabled),
      ]);
    } catch (_) {
      // Fresh install / no legacy plugin data / platform quirk — nothing
      // to carry over. Not fatal either way.
    } finally {
      await _prefs.setBool(_kMigrationDoneKey, true);
    }
  }
}
