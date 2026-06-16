// lib/services/settings_service.dart
//
// Application settings models and persistence for AniStream.
// Replaces the Wails/Go backend calls (GetResolution, UpdateResolution,
// GetEcchiFilter, GetTranscoder, GetUpscaleMethod, etc.) with
// shared_preferences-backed storage.
//
// Required pubspec dependency:
//   shared_preferences: ^2.3.0

import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Models
// ════════════════════════════════════════════════════════════════════════════

/// Startup window resolution, mirroring the [resolutions] array in
/// SettingsMenu.svelte.
class AppResolution {
  final int width;
  final int height;
  final String label;

  const AppResolution({
    required this.width,
    required this.height,
    required this.label,
  });

  /// Canonical preset list shown in [_GeneralTab], ordered by ascending quality.
  static const List<AppResolution> presets = [
    AppResolution(width: 1280, height: 720,  label: '720p HD'),
    AppResolution(width: 1600, height: 900,  label: '900p HD+'),
    AppResolution(width: 1920, height: 1080, label: '1080p Full HD'),
    AppResolution(width: 2560, height: 1440, label: '1440p QHD'),
  ];

  @override
  bool operator ==(Object other) =>
      other is AppResolution && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Video transcoder descriptor, mirroring the [encoders] array in
/// SettingsMenu.svelte.
class AppEncoder {
  final String id;
  final String name;
  final String description;

  const AppEncoder({
    required this.id,
    required this.name,
    required this.description,
  });

  static const List<AppEncoder> presets = [
    AppEncoder(
      id: 'libx264',
      name: 'Software',
      description: 'Compatible with all systems.',
    ),
    AppEncoder(
      id: 'h264_nvenc',
      name: 'NVENC',
      description: 'For NVIDIA graphics cards.',
    ),
    AppEncoder(
      id: 'h264_amf',
      name: 'AMF',
      description: 'For AMD graphics cards.',
    ),
    AppEncoder(
      id: 'h264_qsv',
      name: 'QuickSync',
      description: 'For Intel integrated graphics.',
    ),
    AppEncoder(
      id: 'h264_videotoolbox',
      name: 'Apple Silicon',
      description: 'For M1/M2/M3 Mac users.',
    ),
  ];
}

/// Upscaling algorithm descriptor, mirroring the [upscalers] array in
/// SettingsMenu.svelte.
class AppUpscaler {
  final String id;
  final String name;
  final String description;

  const AppUpscaler({
    required this.id,
    required this.name,
    required this.description,
  });

  static const List<AppUpscaler> presets = [
    AppUpscaler(
      id: '',
      name: 'None',
      description: 'Disable upscaling.',
    ),
    AppUpscaler(
      id: 'lanczos',
      name: 'Lanczos',
      description: 'Sharp, traditional 2D grid scaling.',
    ),
    AppUpscaler(
      id: 'ewa_lanczos',
      name: 'EWA Lanczos',
      description: 'Circular, natural, high-performance reconstruction.',
    ),
    AppUpscaler(
      id: 'ewa_lanczossharp',
      name: 'EWA Lanczos Sharp',
      description: 'Mathematically tweaked EWA for maximum crispness.',
    ),
  ];
}

/// Upscaling target resolution, mirroring [targetResolutions] in
/// SettingsMenu.svelte.
class AppUpscaleResolution {
  final int width;
  final int height;
  final String label;

  const AppUpscaleResolution({
    required this.width,
    required this.height,
    required this.label,
  });

  static const List<AppUpscaleResolution> presets = [
    AppUpscaleResolution(width: 1920, height: 1080, label: '1080p Full HD'),
    AppUpscaleResolution(width: 2560, height: 1440, label: '1440p QHD'),
    AppUpscaleResolution(width: 3840, height: 2160, label: '2160p UHD'),
  ];

  @override
  bool operator ==(Object other) =>
      other is AppUpscaleResolution &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Complete snapshot of all persisted user settings.
/// Passed to and returned from [SettingsService].
class AppSettings {
  final AppResolution resolution;
  final bool filterEcchi;
  final String downloadFolder;
  final String encoderId;
  final bool enableAV1;
  final bool enableOpus;
  final String upscaleMethod;
  final AppUpscaleResolution upscaleResolution;

  const AppSettings({
    required this.resolution,
    required this.filterEcchi,
    required this.downloadFolder,
    required this.encoderId,
    required this.enableAV1,
    required this.enableOpus,
    required this.upscaleMethod,
    required this.upscaleResolution,
  });

  /// Returns factory defaults used on the very first launch before any
  /// settings have been persisted. Mirrors the $state initialisers in
  /// SettingsMenu.svelte.
  factory AppSettings.defaults() => AppSettings(
    resolution: AppResolution.presets.first,
    filterEcchi: true,
    downloadFolder: '',
    encoderId: 'libx264',
    enableAV1: false,
    enableOpus: false,
    upscaleMethod: '',
    upscaleResolution: AppUpscaleResolution.presets.first,
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  Service
// ════════════════════════════════════════════════════════════════════════════

/// Persists and retrieves all AniStream user settings via shared_preferences.
///
/// Drop-in replacement for the Go functions called by SettingsMenu.svelte.
/// One instance can be created per widget — SharedPreferences is internally
/// cached so multiple instances do not cause extra I/O.
///
/// ```dart
/// final service = SettingsService();
/// final settings = await service.load();
/// await service.save(updatedSettings);
/// ```
class SettingsService {
  // ── Preference keys ──────────────────────────────────────────────────────
  static const _kResW        = 'res_width';
  static const _kResH        = 'res_height';
  static const _kFilterEcchi = 'filter_ecchi';
  static const _kFolder      = 'download_folder';
  static const _kEncoder     = 'encoder_id';
  static const _kEnableAV1   = 'enable_av1';
  static const _kEnableOpus  = 'enable_opus';
  static const _kUpscaleM    = 'upscale_method';
  static const _kUpscaleResW = 'upscale_res_w';
  static const _kUpscaleResH = 'upscale_res_h';

  /// Reads all settings from shared_preferences, falling back to
  /// [AppSettings.defaults] for any key not yet written.
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    // ── Startup resolution ─────────────────────────────────────────────────
    final resW = prefs.getInt(_kResW) ?? 1280;
    final resH = prefs.getInt(_kResH) ?? 720;
    final resolution = AppResolution.presets.firstWhere(
      (r) => r.width == resW && r.height == resH,
      orElse: () => AppResolution.presets.first,
    );

    // ── Encoder — mirrors AV1 string mangling from SettingsMenu.svelte ────
    // The Svelte version persists AV1 variants with an "av1_" prefix
    // (e.g. "av1_nvenc"). We strip that back to "h264_" on load and set
    // enableAV1 = true so the two fields remain in sync.
    String encoderId = prefs.getString(_kEncoder) ?? 'libx264';
    bool enableAV1   = prefs.getBool(_kEnableAV1) ?? false;
    if (encoderId.startsWith('av1_')) {
      encoderId = encoderId.replaceFirst('av1_', 'h264_');
      enableAV1 = true;
    }

    // ── Upscale resolution ─────────────────────────────────────────────────
    final upW = prefs.getInt(_kUpscaleResW) ?? 1920;
    final upH = prefs.getInt(_kUpscaleResH) ?? 1080;
    final upscaleRes = AppUpscaleResolution.presets.firstWhere(
      (r) => r.width == upW && r.height == upH,
      orElse: () => AppUpscaleResolution.presets.first,
    );

    return AppSettings(
      resolution:        resolution,
      filterEcchi:       prefs.getBool(_kFilterEcchi)   ?? true,
      downloadFolder:    prefs.getString(_kFolder)       ?? '',
      encoderId:         encoderId,
      enableAV1:         enableAV1,
      enableOpus:        prefs.getBool(_kEnableOpus)     ?? false,
      upscaleMethod:     prefs.getString(_kUpscaleM)     ?? '',
      upscaleResolution: upscaleRes,
    );
  }

  /// Persists [settings] to shared_preferences.
  ///
  /// Applies AV1 encoder-id mangling before writing, mirroring the
  /// [handleSave] function in SettingsMenu.svelte: an encoder of
  /// "h264_nvenc" with enableAV1=true is stored as "av1_nvenc".
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    String finalEncoder = settings.encoderId;
    if (settings.enableAV1 && finalEncoder.startsWith('h264_')) {
      finalEncoder = finalEncoder.replaceFirst('h264_', 'av1_');
    }

    // Write all keys concurrently — SharedPreferences batches platform writes.
    await Future.wait([
      prefs.setInt   (_kResW,        settings.resolution.width),
      prefs.setInt   (_kResH,        settings.resolution.height),
      prefs.setBool  (_kFilterEcchi, settings.filterEcchi),
      prefs.setString(_kFolder,      settings.downloadFolder),
      prefs.setString(_kEncoder,     finalEncoder),
      prefs.setBool  (_kEnableAV1,   settings.enableAV1),
      prefs.setBool  (_kEnableOpus,  settings.enableOpus),
      prefs.setString(_kUpscaleM,    settings.upscaleMethod),
      prefs.setInt   (_kUpscaleResW, settings.upscaleResolution.width),
      prefs.setInt   (_kUpscaleResH, settings.upscaleResolution.height),
    ]);
  }
}
