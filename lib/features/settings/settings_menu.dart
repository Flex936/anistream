import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import 'services/settings_service.dart';
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
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
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

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

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
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings.'), backgroundColor: AppPalette.statusCancelled),
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
                : const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                decoration: BoxDecoration(
                  color: AppPalette.base.withValues(alpha: 0.80),
                  border: isMobile ? null : Border(left: BorderSide(color: AppPalette.border.withValues(alpha: 0.5))),
                  boxShadow: [BoxShadow(color: AppPalette.black.withValues(alpha: 0.5), blurRadius: 40)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── HEADER ──
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Settings', style: TextStyle(color: AppPalette.textMain, fontSize: 26, fontWeight: FontWeight.bold)),
                          _CloseButton(onPressed: () => Navigator.of(context).pop()),
                        ],
                      ),
                    ),

                    // ── CONTENT ──
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppPalette.primary)))
                          : ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              children: [
                                const SectionLabel(label: 'Content Preferences'),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Filter Ecchi / NSFW', style: TextStyle(color: AppPalette.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                                          SizedBox(height: 4),
                                          Text('Automatically hide borderline adult content from search results.', style: TextStyle(color: AppPalette.textMuted, fontSize: 12, height: 1.4)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ToggleSwitch(value: _filterEcchi, onChanged: (v) => setState(() => _filterEcchi = v)),
                                  ],
                                ),
                                
                                // ── NEW PLAYBACK SECTION ──
                                const SizedBox(height: 32),
                                const Divider(color: AppPalette.border),
                                const SizedBox(height: 32),

                                const SectionLabel(label: 'Playback Preferences'),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Auto-Play Recommended', style: TextStyle(color: AppPalette.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                                          SizedBox(height: 4),
                                          Text('Skip the release list and instantly stream the highest-rated torrent.', style: TextStyle(color: AppPalette.textMuted, fontSize: 12, height: 1.4)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ToggleSwitch(value: _autoPlayRecommended, onChanged: (v) => setState(() => _autoPlayRecommended = v)),
                                  ],
                                ),

                                if (_isDesktop) ...[
                                  const SizedBox(height: 32),
                                  const Divider(color: AppPalette.border),
                                  const SizedBox(height: 32),
                                  
                                  const SectionLabel(label: 'Playback Engine'),
                                  const SizedBox(height: 16),
                                  const Text('Hardware Decoding', style: TextStyle(color: AppPalette.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  const Text('Use your GPU to decode video streams for vastly improved performance and lower battery usage.', style: TextStyle(color: AppPalette.textMuted, fontSize: 12, height: 1.4)),
                                  const SizedBox(height: 16),
                                  
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: AppPalette.overlay,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppPalette.border),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _hardwareDecoding,
                                        dropdownColor: AppPalette.overlay,
                                        icon: const Icon(Icons.expand_more_rounded, color: AppPalette.textMuted),
                                        isExpanded: true,
                                        style: const TextStyle(color: AppPalette.textMain, fontSize: 14, fontWeight: FontWeight.w500),
                                        items: const [
                                          DropdownMenuItem(value: 'auto', child: Text('Auto (Safe Default)')),
                                          DropdownMenuItem(value: 'cuda-copy', child: Text('NVIDIA (CUDA)')),
                                          DropdownMenuItem(value: 'd3d11va-copy', child: Text('Windows Native (D3D11VA)')),
                                          DropdownMenuItem(value: 'videotoolbox-copy', child: Text('Apple Silicon (VideoToolbox)')),
                                          DropdownMenuItem(value: 'none', child: Text('Software Only (CPU)')),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) setState(() => _hardwareDecoding = val);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),

                    // ── FOOTER ──
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppPalette.base.withValues(alpha: 0.5),
                        border: const Border(top: BorderSide(color: AppPalette.border)),
                      ),
                      child: FilledButton(
                        onPressed: _saving ? null : _handleSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.primary,
                          foregroundColor: AppPalette.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppPalette.white)))
                            : const Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
            color: _hovered ? AppPalette.statusCancelled.withValues(alpha: 0.12) : AppPalette.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.close_rounded, size: 24, color: _hovered ? AppPalette.statusCancelled : AppPalette.textMuted),
        ),
      ),
    );
  }
}