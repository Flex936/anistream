import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../services/settings_service.dart';
import 'settings/settings_tabs.dart';

Future<void> showSettingsMenu(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Settings',
    barrierColor: Colors.black.withValues(alpha: 0.60),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (_, _, _) => const SettingsMenu(),
  );
}

enum SettingsTab { general, playback, upscale }

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({super.key});

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  final _service = SettingsService();

  SettingsTab _activeTab = SettingsTab.general;
  bool _loading = true;
  bool _saving = false;

  late bool _filterEcchi;
  late String _downloadFolder;
  late String _encoderId;
  late bool _enableAV1;
  late bool _enableOpus;
  late String _upscaleMethod;
  late AppUpscaleResolution _upscaleResolution;

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
      _downloadFolder = s.downloadFolder;
      _encoderId = s.encoderId;
      _enableAV1 = s.enableAV1;
      _enableOpus = s.enableOpus;
      _upscaleMethod = s.upscaleMethod;
      _upscaleResolution = s.upscaleResolution;
      _loading = false;
    });
  }

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      await _service.save(
        AppSettings(
          filterEcchi: _filterEcchi,
          downloadFolder: _downloadFolder,
          encoderId: _encoderId,
          enableAV1: _enableAV1,
          enableOpus: _enableOpus,
          upscaleMethod: _upscaleMethod,
          upscaleResolution: _upscaleResolution,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppPalette.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDownloadFolder() async {
    String? path = await FilePicker.getDirectoryPath();
    if (path != null && mounted) {
      setState(() => _downloadFolder = path);
    }
  }

  Widget _buildTabContent() => switch (_activeTab) {
    SettingsTab.general => GeneralTab(
      key: const ValueKey(SettingsTab.general),
      filterEcchi: _filterEcchi,
      downloadFolder: _downloadFolder,
      onFilterEcchiChanged: (v) => setState(() => _filterEcchi = v),
      onPickDownloadFolder: _pickDownloadFolder,
    ),
    SettingsTab.playback => const PlaybackTab(
      key: ValueKey(SettingsTab.playback),
    ),
    SettingsTab.upscale => const UpscaleTab(key: ValueKey(SettingsTab.upscale)),
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 768, maxHeight: 600),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.surface,
              border: Border.all(color: AppPalette.border),
            ),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppPalette.primary,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SettingsSidebar(
                        activeTab: _activeTab,
                        onTabSelected: (t) => setState(() => _activeTab = t),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      32,
                                      32,
                                      32,
                                      16,
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      switchInCurve: Curves.easeOut,
                                      switchOutCurve: Curves.easeIn,
                                      child: _buildTabContent(),
                                    ),
                                  ),
                                ),
                                _SettingsFooter(
                                  saving: _saving,
                                  onSave: _handleSave,
                                ),
                              ],
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: _CloseButton(
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  final SettingsTab activeTab;
  final ValueChanged<SettingsTab> onTabSelected;

  const _SettingsSidebar({
    required this.activeTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppPalette.base,
        border: Border(right: BorderSide(color: AppPalette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Settings',
              style: TextStyle(
                color: AppPalette.textMain,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SideNavButton(
            icon: Icons.monitor_outlined,
            label: 'General',
            active: activeTab == SettingsTab.general,
            onPressed: () => onTabSelected(SettingsTab.general),
          ),
          const SizedBox(height: 4),
          _SideNavButton(
            icon: Icons.movie_filter_outlined,
            label: 'Playback',
            active: activeTab == SettingsTab.playback,
            onPressed: () => onTabSelected(SettingsTab.playback),
          ),
          const SizedBox(height: 4),
          _SideNavButton(
            icon: Icons.auto_awesome_outlined,
            label: 'Upscale',
            active: activeTab == SettingsTab.upscale,
            onPressed: () => onTabSelected(SettingsTab.upscale),
          ),
        ],
      ),
    );
  }
}

class _SideNavButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  const _SideNavButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  @override
  State<_SideNavButton> createState() => _SideNavButtonState();
}

class _SideNavButtonState extends State<_SideNavButton> {
  bool _hovered = false;

  Color get _background => widget.active
      ? AppPalette.primary.withValues(alpha: 0.15)
      : _hovered
      ? AppPalette.surface
      : Colors.transparent;
  Color get _foreground => widget.active
      ? AppPalette.primary
      : _hovered
      ? AppPalette.textMain
      : AppPalette.textMuted;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: _foreground, size: 18),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: _foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _CloseButton({required this.onPressed});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hovered
                ? AppPalette.statusCancelled.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.close_rounded,
            size: 20,
            color: _hovered ? AppPalette.statusCancelled : AppPalette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SettingsFooter extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;

  const _SettingsFooter({required this.saving, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppPalette.base,
        border: Border(top: BorderSide(color: AppPalette.border)),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: saving ? null : onSave,
          style: FilledButton.styleFrom(
            backgroundColor: AppPalette.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppPalette.primary.withValues(alpha: 0.50),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text(
                  'Save Changes',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}
