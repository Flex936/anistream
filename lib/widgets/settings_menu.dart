// lib/widgets/settings_menu.dart
//
// Application settings overlay for AniStream.
// Translates SettingsMenu.svelte + GeneralTab.svelte into Flutter.
//
// The Playback and Upscale tabs are stubbed — see the TODO markers inside
// [_PlaybackTab] and [_UpscaleTab] when ready to implement them.
//
// Call [showSettingsMenu] to present the modal from any [BuildContext].
//
// Required pubspec dependencies:
//   file_picker:   ^8.0.6   (native folder-picker dialog)
//   window_manager: ^0.3.8  (window resize after saving resolution)

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_palette.dart'; // AppPalette
import '../services/settings_service.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Entry point
// ════════════════════════════════════════════════════════════════════════════

/// Presents the settings overlay over [context].
///
/// Uses [showGeneralDialog] so we can supply a custom fade + zoom-in
/// transition, mirroring the `animate-in fade-in zoom-in-95 duration-200`
/// class on the dialog root in SettingsMenu.svelte.
///
/// ```dart
/// onSettings: () => showSettingsMenu(context),
/// ```
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
          // zoom-in-95 starts at 95 % and eases up to 100 %.
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (_, __, ___) => const SettingsMenu(),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  Tab enum
// ════════════════════════════════════════════════════════════════════════════

enum _SettingsTab { general, playback, upscale }

// ════════════════════════════════════════════════════════════════════════════
//  SettingsMenu
// ════════════════════════════════════════════════════════════════════════════

/// Settings modal — equivalent to SettingsMenu.svelte.
///
/// Rendered as a centred dialog card with a fixed sidebar and a scrollable
/// content area, matching the `max-w-3xl … h-[600px]` layout in Svelte.
class SettingsMenu extends StatefulWidget {
  const SettingsMenu({super.key});

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  final _service = SettingsService();

  _SettingsTab _activeTab = _SettingsTab.general;
  bool _loading = true;
  bool _saving = false;

  // ── Mutable settings state — mirrors the $state variables in SettingsMenu.svelte
  late AppResolution _resolution;
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
      _resolution = s.resolution;
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

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      await _service.save(
        AppSettings(
          resolution: _resolution,
          filterEcchi: _filterEcchi,
          downloadFolder: _downloadFolder,
          encoderId: _encoderId,
          enableAV1: _enableAV1,
          enableOpus: _enableOpus,
          upscaleMethod: _upscaleMethod,
          upscaleResolution: _upscaleResolution,
        ),
      );
      // Resize the native window to match the chosen startup resolution —
      // mirrors WindowSetSize(selectedRes.w, selectedRes.h) in Svelte.
      await windowManager.setSize(
        Size(_resolution.width.toDouble(), _resolution.height.toDouble()),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: AppPalette.statusCancelled,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Folder picker ─────────────────────────────────────────────────────────

  Future<void> _pickDownloadFolder() async {
    // On macOS: ensure NSDocumentsFolderUsageDescription is set in Info.plist.
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && mounted) {
      setState(() => _downloadFolder = path);
    }
  }

  // ── Tab content builder ───────────────────────────────────────────────────

  Widget _buildTabContent() => switch (_activeTab) {
    _SettingsTab.general => _GeneralTab(
      key: const ValueKey(_SettingsTab.general),
      resolution: _resolution,
      filterEcchi: _filterEcchi,
      downloadFolder: _downloadFolder,
      onResolutionChanged: (r) => setState(() => _resolution = r),
      onFilterEcchiChanged: (v) => setState(() => _filterEcchi = v),
      onPickDownloadFolder: _pickDownloadFolder,
    ),
    _SettingsTab.playback => const _PlaybackTab(
      key: ValueKey(_SettingsTab.playback),
    ),
    _SettingsTab.upscale => const _UpscaleTab(
      key: ValueKey(_SettingsTab.upscale),
    ),
  };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      // Keep some margin so the dialog never touches screen edges.
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        // max-w-3xl (768 px) h-[600px] from SettingsMenu.svelte.
        constraints: const BoxConstraints(maxWidth: 768, maxHeight: 600),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.border),
            ),
            child: _loading
                ? const _LoadingPane()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Sidebar ────────────────────────────────────────────
                      _SettingsSidebar(
                        activeTab: _activeTab,
                        onTabSelected: (t) => setState(() => _activeTab = t),
                      ),

                      // ── Content + footer ───────────────────────────────────
                      Expanded(
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Scrollable tab body
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      32,
                                      32,
                                      32,
                                      16,
                                    ),
                                    // AnimatedSwitcher fades between tabs,
                                    // mirroring `animate-in fade-in
                                    // slide-in-from-right-4` in GeneralTab.svelte.
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

                                // Save / footer bar
                                _SettingsFooter(
                                  saving: _saving,
                                  onSave: _handleSave,
                                ),
                              ],
                            ),

                            // Close button floats top-right, mirroring the
                            // `absolute top-4 right-4` X button in Svelte.
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

// ════════════════════════════════════════════════════════════════════════════
//  _LoadingPane
// ════════════════════════════════════════════════════════════════════════════

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
        strokeWidth: 2.5,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _SettingsSidebar
// ════════════════════════════════════════════════════════════════════════════

/// Left sidebar with tab navigation — mirrors the `w-64 bg-base border-r`
/// column in SettingsMenu.svelte.
class _SettingsSidebar extends StatelessWidget {
  final _SettingsTab activeTab;
  final ValueChanged<_SettingsTab> onTabSelected;

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
            active: activeTab == _SettingsTab.general,
            onPressed: () => onTabSelected(_SettingsTab.general),
          ),
          const SizedBox(height: 4),
          _SideNavButton(
            icon: Icons.movie_filter_outlined,
            label: 'Playback',
            active: activeTab == _SettingsTab.playback,
            onPressed: () => onTabSelected(_SettingsTab.playback),
          ),
          const SizedBox(height: 4),
          _SideNavButton(
            icon: Icons.auto_awesome_outlined,
            label: 'Upscale',
            active: activeTab == _SettingsTab.upscale,
            onPressed: () => onTabSelected(_SettingsTab.upscale),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _SideNavButton
// ════════════════════════════════════════════════════════════════════════════

/// Individual tab button in the settings sidebar.
///
/// Active state mirrors `bg-primary/20 text-primary`; hover mirrors
/// `hover:bg-surface hover:text-main` from SettingsMenu.svelte.
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

  Color get _background {
    if (widget.active) return AppPalette.primary.withValues(alpha: 0.15);
    if (_hovered) return AppPalette.surface;
    return Colors.transparent;
  }

  Color get _foreground {
    if (widget.active) return AppPalette.primary;
    if (_hovered) return AppPalette.textMain;
    return AppPalette.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
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

// ════════════════════════════════════════════════════════════════════════════
//  _CloseButton
// ════════════════════════════════════════════════════════════════════════════

/// X button that dismisses the dialog.
///
/// Mirrors the `hover:text-red-400 hover:bg-red-400/10` close button
/// in SettingsMenu.svelte.
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
      cursor: SystemMouseCursors.click,
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

// ════════════════════════════════════════════════════════════════════════════
//  _SettingsFooter
// ════════════════════════════════════════════════════════════════════════════

/// Save button bar pinned to the bottom of the dialog.
///
/// Mirrors the `border-t border-border p-4 bg-base flex justify-end`
/// footer in SettingsMenu.svelte, including the disabled+spinner state
/// while [saving] is true.
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

// ════════════════════════════════════════════════════════════════════════════
//  _GeneralTab   (implements GeneralTab.svelte)
// ════════════════════════════════════════════════════════════════════════════

class _GeneralTab extends StatelessWidget {
  final AppResolution resolution;
  final bool filterEcchi;
  final String downloadFolder;
  final ValueChanged<AppResolution> onResolutionChanged;
  final ValueChanged<bool> onFilterEcchiChanged;
  final VoidCallback onPickDownloadFolder;

  const _GeneralTab({
    super.key,
    required this.resolution,
    required this.filterEcchi,
    required this.downloadFolder,
    required this.onResolutionChanged,
    required this.onFilterEcchiChanged,
    required this.onPickDownloadFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Heading ───────────────────────────────────────────────────────
        const _TabHeading(title: 'General Settings'),
        const SizedBox(height: 24),

        // ── Startup resolution ────────────────────────────────────────────
        const _SectionLabel(label: 'Startup Resolution'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            // Fixed height avoids childAspectRatio gymnastics when the
            // parent width is unknown at build time.
            mainAxisExtent: 64,
          ),
          itemCount: AppResolution.presets.length,
          itemBuilder: (_, i) {
            final preset = AppResolution.presets[i];
            return _ResolutionCard(
              resolution: preset,
              selected: preset == resolution,
              onTap: () => onResolutionChanged(preset),
            );
          },
        ),

        // ── Filter ecchi ──────────────────────────────────────────────────
        const SizedBox(height: 24),
        const Divider(color: AppPalette.border, height: 1),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FILTER ECCHI CONTENT',
                  style: TextStyle(
                    color: AppPalette.textMain,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Hide borderline NSFW shows.',
                  style: TextStyle(color: AppPalette.textMuted, fontSize: 12),
                ),
              ],
            ),
            _ToggleSwitch(value: filterEcchi, onChanged: onFilterEcchiChanged),
          ],
        ),

        // ── Download directory ────────────────────────────────────────────
        const SizedBox(height: 20),
        const Divider(color: AppPalette.border, height: 1),
        const SizedBox(height: 20),
        const _SectionLabel(label: 'Download Directory'),
        const SizedBox(height: 4),
        const Text(
          'Change your temporary downloads folder.',
          style: TextStyle(color: AppPalette.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _FolderInput(path: downloadFolder, onTap: onPickDownloadFolder),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _PlaybackTab  (TODO)
// ════════════════════════════════════════════════════════════════════════════

class _PlaybackTab extends StatelessWidget {
  const _PlaybackTab({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement PlaybackTab.svelte
    //   - Encoder selector (AppEncoder.presets → _RadioCard list)
    //   - Enable AV1 toggle (_ToggleSwitch)
    //   - Enable Opus toggle (_ToggleSwitch)
    //   Wire changes back through callbacks on [_SettingsMenuState]:
    //   _encoderId, _enableAV1, _enableOpus.
    return const _TodoPane(tabName: 'Playback');
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _UpscaleTab   (TODO)
// ════════════════════════════════════════════════════════════════════════════

class _UpscaleTab extends StatelessWidget {
  const _UpscaleTab({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement UpscaleTab.svelte
    //   - Upscaling method selector (AppUpscaler.presets → _RadioCard list)
    //   - Target resolution selector (AppUpscaleResolution.presets → 2-col grid)
    //   Wire changes back through callbacks on [_SettingsMenuState]:
    //   _upscaleMethod, _upscaleResolution.
    return const _TodoPane(tabName: 'Upscale');
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _TodoPane
// ════════════════════════════════════════════════════════════════════════════

/// Placeholder shown for tabs not yet implemented.
class _TodoPane extends StatelessWidget {
  final String tabName;
  const _TodoPane({required this.tabName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Match the rough height of the general tab so the dialog doesn't jump
      // in size when switching.
      height: 340,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.construction_rounded,
              color: AppPalette.textMuted,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '$tabName settings coming soon.',
              style: const TextStyle(color: AppPalette.textMuted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Shared tab sub-widgets
// ════════════════════════════════════════════════════════════════════════════

/// Large bold heading at the top of each tab content area.
class _TabHeading extends StatelessWidget {
  final String title;
  const _TabHeading({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppPalette.textMain,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Small all-caps section label, mirroring `text-xs font-semibold text-muted
/// uppercase tracking-wider` in GeneralTab.svelte.
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppPalette.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _ResolutionCard
// ════════════════════════════════════════════════════════════════════════════

/// Selectable resolution tile in the 2-column startup-resolution grid.
///
/// Active state mirrors `border-primary bg-primary/10`; hover mirrors
/// `hover:border-gray-500` from GeneralTab.svelte.
class _ResolutionCard extends StatefulWidget {
  final AppResolution resolution;
  final bool selected;
  final VoidCallback onTap;

  const _ResolutionCard({
    required this.resolution,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ResolutionCard> createState() => _ResolutionCardState();
}

class _ResolutionCardState extends State<_ResolutionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? AppPalette.primary.withValues(alpha: 0.10)
                : AppPalette.base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: 2,
              color: sel
                  ? AppPalette.primary
                  : _hovered
                  ? AppPalette.textMuted
                  : AppPalette.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // e.g. "1080p Full HD"
              Text(
                widget.resolution.label,
                style: TextStyle(
                  color: sel ? AppPalette.primary : const Color(0xFFE2E8F0),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              // e.g. "1920 × 1080"
              Text(
                '${widget.resolution.width} × ${widget.resolution.height}',
                style: TextStyle(
                  color: sel
                      ? AppPalette.primary.withValues(alpha: 0.70)
                      : AppPalette.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _FolderInput
// ════════════════════════════════════════════════════════════════════════════

/// Read-only path display that opens the native folder-picker on tap.
///
/// Mirrors the folder-open button + path input combination in
/// GeneralTab.svelte. Making the whole row tappable (not just the icon)
/// improves click target size on desktop.
class _FolderInput extends StatefulWidget {
  final String path;
  final VoidCallback onTap;

  const _FolderInput({required this.path, required this.onTap});

  @override
  State<_FolderInput> createState() => _FolderInputState();
}

class _FolderInputState extends State<_FolderInput> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.path.isEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppPalette.base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: 2,
              color: _hovered ? AppPalette.primary : AppPalette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 18,
                color: _hovered ? AppPalette.primary : AppPalette.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEmpty ? 'Click to select a folder…' : widget.path,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isEmpty ? AppPalette.textMuted : AppPalette.textMain,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _ToggleSwitch
// ════════════════════════════════════════════════════════════════════════════

/// Custom animated toggle switch, replacing ToggleSwitch.svelte.
///
/// Uses [AnimatedContainer] for the track colour and [AnimatedAlign] for
/// the thumb slide — both at 200 ms to match the CSS transition duration.
class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: value ? AppPalette.primary : AppPalette.overlay,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? AppPalette.primary : AppPalette.border,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
