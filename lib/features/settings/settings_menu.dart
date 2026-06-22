import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';

import '../../shared/widgets/toast.dart';
import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_service.dart';
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
  final _service = SettingsService();

  bool _loading = true;
  bool _saving = false;

  late bool _filterEcchi;
  late String _hardwareDecoding;
  late bool _autoPlayRecommended;
  late bool _autoSkip;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _service.load();
    if (!mounted) return;
    setState(() {
      _filterEcchi = s.filterEcchi;
      _hardwareDecoding = s.hardwareDecoding;
      _autoPlayRecommended = s.autoPlayRecommended;
      _autoSkip = s.autoSkip;
      _loading = false;
    });
  }

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      await _service.save(
        AppSettings(
          filterEcchi: _filterEcchi,
          hardwareDecoding: _hardwareDecoding,
          autoPlayRecommended: _autoPlayRecommended,
          autoSkip: _autoSkip,
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

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: isMobile ? MediaQuery.of(context).size.width : 450,
          height: double.infinity,
          child: ClipRRect(
            borderRadius: isMobile
                ? BorderRadius.zero
                : const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    bottomLeft: Radius.circular(24),
                  ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                decoration: BoxDecoration(
                  color: AppPalette.base.withValues(alpha: 0.65),
                  border: isMobile
                      ? null
                      : Border(
                          left: BorderSide(
                            color: AppPalette.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                          top: BorderSide(
                            color: AppPalette.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                          bottom: BorderSide(
                            color: AppPalette.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.black.withValues(alpha: 0.6),
                      blurRadius: 40,
                    ),
                  ],
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
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                  AppPalette.primary,
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
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
                                      title: 'Auto-Play Recommended',
                                      subtitle:
                                          'Skip the release list and instantly stream the highest-rated torrent.',
                                      value: _autoPlayRecommended,
                                      onChanged: (v) => setState(
                                        () => _autoPlayRecommended = v,
                                      ),
                                    ),
                                    SettingRowTile(
                                      title: 'Auto-Skip',
                                      subtitle:
                                          'Skip the Openings and Endings of anime if available.',
                                      value: _autoSkip,
                                      onChanged: (v) =>
                                          setState(() => _autoSkip = v),
                                    ),
                                  ],
                                ),
                                if (_isDesktop)
                                  SettingsSection(
                                    label: 'Playback Engine',
                                    showDividerAbove: true,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(
                                                () => _hardwareDecoding = val,
                                              );
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
      ),
    );
  }
}
