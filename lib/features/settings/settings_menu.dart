import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/settings/settings_scope.dart';
import '../../core/settings/settings_service.dart';
import '../../core/theme/app_palette.dart';
import '../../shared/widgets/frosted_container.dart';
import '../../shared/widgets/toast.dart';
import 'widgets/settings_components.dart';

Future<void> showSettingsMenu(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Settings',
    barrierColor: AppPalette.black.withValues(alpha: 0.40),
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (context, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      );
    },
    pageBuilder: (_, _, _) => const SettingsMenu(),
  );
}

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({super.key});
  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  bool _saving = false;
  bool _pinging = false;

  // ── Seeded from SettingsScope in didChangeDependencies instead of a
  // second independent SettingsService().load() call — the values are
  // already sitting in the app-wide scope by the time this dialog opens. ──
  bool _hydrated = false;

  late bool _filterEcchi;
  late String _hardwareDecoding;
  late String _androidHwDec;
  late bool _autoPlayEnabled;
  late bool _autoSkip;
  late bool _uiPerformanceMode;
  late String _videoFilterQuality;

  late bool _serverMode;
  late final TextEditingController _serverUrlController;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;
    _hydrated = true;

    final s = SettingsScope.of(context, listen: false).settings;
    _filterEcchi = s.filterEcchi;
    _hardwareDecoding = s.hardwareDecoding;
    _androidHwDec = s.androidHwDec;
    _autoPlayEnabled = s.autoPlayEnabled;
    _autoSkip = s.autoSkip;
    _uiPerformanceMode = s.uiPerformanceMode;
    _videoFilterQuality = s.videoFilterQuality;
    _serverMode = s.serverMode;
    _serverUrlController.text = s.serverUrl;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      await SettingsScope.of(context, listen: false).update(
        AppSettings(
          filterEcchi: _filterEcchi,
          hardwareDecoding: _hardwareDecoding,
          androidHwDec: _androidHwDec,
          autoPlayEnabled: _autoPlayEnabled,
          autoSkip: _autoSkip,
          uiPerformanceMode: _uiPerformanceMode,
          videoFilterQuality: _videoFilterQuality,
          serverMode: _serverMode,
          serverUrl: _serverUrlController.text.trim(),
        ),
      );
      if (mounted) {
        AppleSnackBar.show(
          context: context,
          message: 'Settings saved successfully',
          icon: Icons.check_circle_rounded,
          iconColor: AppPalette.statusReleasing,
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        AppleSnackBar.show(
          context: context,
          message: 'Failed to save settings',
          icon: Icons.error_outline_rounded,
          iconColor: AppPalette.statusCancelled,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Pings the server's /api/health endpoint and shows a toast with the result.
  Future<void> _pingServer() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _pinging = true);
    try {
      final resp = await http
          .get(Uri.parse('$url/api/health'))
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        AppleSnackBar.show(
          context: context,
          message: 'Server found and reachable!',
          icon: Icons.check_circle_rounded,
          iconColor: AppPalette.statusReleasing,
        );
      } else {
        AppleSnackBar.show(
          context: context,
          message: 'Server responded with HTTP ${resp.statusCode}',
          icon: Icons.warning_amber_rounded,
          iconColor: AppPalette.accent,
        );
      }
    } catch (_) {
      if (mounted) {
        AppleSnackBar.show(
          context: context,
          message: 'Cannot reach server. Check URL and LAN connection.',
          icon: Icons.wifi_off_rounded,
          iconColor: AppPalette.statusCancelled,
        );
      }
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: isMobile ? MediaQuery.sizeOf(context).width : 450,
          height: double.infinity,
          // ── Was an unconditional ClipRRect + BackdropFilter(sigma: 50)
          // regardless of _uiPerformanceMode. Routed through the same
          // FrostedContainer every other glass surface in the app uses,
          // so this panel now actually drops its own blur when the setting
          // is on (and updates live as the user flips the switch below, before even saving). ──
          child: FrostedContainer(
            uiPerformanceMode: _uiPerformanceMode,
            sigma: 50,
            borderRadius: isMobile
                ? BorderRadius.zero
                : const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    bottomLeft: Radius.circular(24),
                  ),
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.base.withValues(
                  alpha: _uiPerformanceMode ? 0.97 : 0.65,
                ),
                border: isMobile
                    ? null
                    : Border(
                        left: BorderSide(
                          color: AppPalette.white.withValues(alpha: 0.1),
                        ),
                        top: BorderSide(
                          color: AppPalette.white.withValues(alpha: 0.1),
                        ),
                        bottom: BorderSide(
                          color: AppPalette.white.withValues(alpha: 0.1),
                        ),
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 24, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Settings',
                          style: TextStyle(
                            color: AppPalette.textMain,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SettingsCloseButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    // ── Values are hydrated synchronously in
                    // didChangeDependencies (before the first build), so
                    // there's no longer a loading spinner state to show
                    // here — SettingsScope already holds the data. ──
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        SettingsSection(
                          label: 'Content Preferences',
                          children: [
                            SettingRowTile(
                              title: 'Filter Ecchi',
                              subtitle:
                                  'Automatically hide borderline adult content from search results.',
                              value: _filterEcchi,
                              onChanged: (v) =>
                                  setState(() => _filterEcchi = v),
                              autofocus: true,
                            ),
                          ],
                        ),

                        SettingsSection(
                          label: 'Playback Preferences',
                          showDividerAbove: true,
                          children: [
                            SettingRowTile(
                              title: 'Auto-Play',
                              subtitle:
                                  'Skip the release list and instantly stream the highest-rated torrent.',
                              value: _autoPlayEnabled,
                              onChanged: (v) =>
                                  setState(() => _autoPlayEnabled = v),
                            ),
                            SettingRowTile(
                              title: 'Auto-Skip',
                              subtitle:
                                  'Skip the Openings and Endings of anime if available.',
                              value: _autoSkip,
                              onChanged: (v) => setState(() => _autoSkip = v),
                            ),
                            SettingRowTile(
                              title: 'UI Performance Mode',
                              subtitle:
                                  'Disables frosted glass, blurs, and animations. Highly recommended for Android TVs.',
                              value: _uiPerformanceMode,
                              onChanged: (v) =>
                                  setState(() => _uiPerformanceMode = v),
                            ),
                            const SizedBox(height: 16),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Video Scaling Quality',
                                    style: TextStyle(
                                      color: AppPalette.textMain,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Determines how the GPU scales video frames. Set to "None" if 1080p stutters on your TV.',
                                    style: TextStyle(
                                      color: AppPalette.textMuted,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: SettingsDropdown(
                                value: _videoFilterQuality,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'high',
                                    child: Text('High (Best Anti-Aliasing)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'medium',
                                    child: Text('Medium'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'low',
                                    child: Text('Low (Flutter Default)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'none',
                                    child: Text('None (Raw Pixels / Best FPS)'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _videoFilterQuality = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        SettingsSection(
                          label: 'Remote Server',
                          showDividerAbove: true,
                          children: [
                            SettingRowTile(
                              title: 'Use Remote Server',
                              subtitle:
                                  'Offload torrenting to a PC or NAS on your LAN. The TV only decodes and renders video.',
                              value: _serverMode,
                              onChanged: (v) => setState(() => _serverMode = v),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              child: _serverMode
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SettingsTextField(
                                            controller: _serverUrlController,
                                            hint: 'http://192.168.1.100:7878',
                                            label: 'Server URL',
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: _pinging
                                                      ? null
                                                      : _pingServer,
                                                  icon: _pinging
                                                      ? const SizedBox(
                                                          width: 14,
                                                          height: 14,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            valueColor:
                                                                AlwaysStoppedAnimation(
                                                                  AppPalette
                                                                      .primary,
                                                                ),
                                                          ),
                                                        )
                                                      : const Icon(
                                                          Icons
                                                              .wifi_find_rounded,
                                                          size: 16,
                                                        ),
                                                  label: Text(
                                                    _pinging
                                                        ? 'Checking…'
                                                        : 'Test Connection',
                                                  ),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        AppPalette.primary,
                                                    side: const BorderSide(
                                                      color: AppPalette.primary,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Run anistream-server on any PC, NAS, or Raspberry Pi on your LAN. '
                                            'See anistream_server/README.md for build instructions.',
                                            style: TextStyle(
                                              color: AppPalette.textMuted
                                                  .withValues(alpha: 0.7),
                                              fontSize: 11,
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),

                        if (_isDesktop)
                          SettingsSection(
                            label: 'Desktop Playback Engine',
                            showDividerAbove: true,
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hardware Decoding',
                                      style: TextStyle(
                                        color: AppPalette.textMain,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Use your GPU to decode video streams for vastly improved performance and lower battery usage.',
                                      style: TextStyle(
                                        color: AppPalette.textMuted,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: SettingsDropdown(
                                  value: _hardwareDecoding,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'auto',
                                      child: Text('Auto (Safe Default)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'cuda-copy',
                                      child: Text('NVIDIA (CUDA)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'd3d11va-copy',
                                      child: Text('Windows Native (D3D11VA)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'videotoolbox-copy',
                                      child: Text(
                                        'Apple Silicon (VideoToolbox)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'none',
                                      child: Text('Software Only (CPU)'),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _hardwareDecoding = val);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),

                        if (Platform.isAndroid)
                          SettingsSection(
                            label: 'Android Playback Engine',
                            showDividerAbove: true,
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hardware Decoding (Android)',
                                      style: TextStyle(
                                        color: AppPalette.textMain,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Phones run best on "mediacodec" (Zero-Copy). Android TVs with weak drivers may crash and require "mediacodec-copy".',
                                      style: TextStyle(
                                        color: AppPalette.textMuted,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: SettingsDropdown(
                                  value: _androidHwDec,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'mediacodec-copy',
                                      child: Text(
                                        'mediacodec-copy (Safe / TV Mode)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'mediacodec',
                                      child: Text(
                                        'mediacodec (Zero-Copy / Fast)',
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _androidHwDec = val);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppPalette.base.withValues(alpha: 0.4),
                      border: Border(
                        top: BorderSide(
                          color: AppPalette.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: FilledButton(
                      onPressed: _saving ? null : _handleSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.primary,
                        foregroundColor: AppPalette.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  AppPalette.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
