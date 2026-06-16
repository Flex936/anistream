import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Models
// ════════════════════════════════════════════════════════════════════════════

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
    AppUpscaler(id: '', name: 'None', description: 'Disable upscaling.'),
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

class AppSettings {
  final bool filterEcchi;
  final String downloadFolder;
  final String encoderId;
  final bool enableAV1;
  final bool enableOpus;
  final String upscaleMethod;
  final AppUpscaleResolution upscaleResolution;

  const AppSettings({
    required this.filterEcchi,
    required this.downloadFolder,
    required this.encoderId,
    required this.enableAV1,
    required this.enableOpus,
    required this.upscaleMethod,
    required this.upscaleResolution,
  });

  factory AppSettings.defaults() => AppSettings(
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

class SettingsService {
  static const _kFilterEcchi = 'filter_ecchi';
  static const _kFolder = 'download_folder';
  static const _kEncoder = 'encoder_id';
  static const _kEnableAV1 = 'enable_av1';
  static const _kEnableOpus = 'enable_opus';
  static const _kUpscaleM = 'upscale_method';
  static const _kUpscaleResW = 'upscale_res_w';
  static const _kUpscaleResH = 'upscale_res_h';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    String encoderId = prefs.getString(_kEncoder) ?? 'libx264';
    bool enableAV1 = prefs.getBool(_kEnableAV1) ?? false;
    if (encoderId.startsWith('av1_')) {
      encoderId = encoderId.replaceFirst('av1_', 'h264_');
      enableAV1 = true;
    }

    final upW = prefs.getInt(_kUpscaleResW) ?? 1920;
    final upH = prefs.getInt(_kUpscaleResH) ?? 1080;
    final upscaleRes = AppUpscaleResolution.presets.firstWhere(
      (r) => r.width == upW && r.height == upH,
      orElse: () => AppUpscaleResolution.presets.first,
    );

    return AppSettings(
      filterEcchi: prefs.getBool(_kFilterEcchi) ?? true,
      downloadFolder: prefs.getString(_kFolder) ?? '',
      encoderId: encoderId,
      enableAV1: enableAV1,
      enableOpus: prefs.getBool(_kEnableOpus) ?? false,
      upscaleMethod: prefs.getString(_kUpscaleM) ?? '',
      upscaleResolution: upscaleRes,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    String finalEncoder = settings.encoderId;
    if (settings.enableAV1 && finalEncoder.startsWith('h264_')) {
      finalEncoder = finalEncoder.replaceFirst('h264_', 'av1_');
    }

    await Future.wait([
      prefs.setBool(_kFilterEcchi, settings.filterEcchi),
      prefs.setString(_kFolder, settings.downloadFolder),
      prefs.setString(_kEncoder, finalEncoder),
      prefs.setBool(_kEnableAV1, settings.enableAV1),
      prefs.setBool(_kEnableOpus, settings.enableOpus),
      prefs.setString(_kUpscaleM, settings.upscaleMethod),
      prefs.setInt(_kUpscaleResW, settings.upscaleResolution.width),
      prefs.setInt(_kUpscaleResH, settings.upscaleResolution.height),
    ]);
  }
}
