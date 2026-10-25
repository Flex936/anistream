import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/widgets/toggle_switch.dart';
import '../services/track_name_parser.dart';

enum _MenuPage { main, subtitles, audio }

/// One selectable subtitle/audio row; engine-agnostic, so any player's
/// tracks fit.
class SettingsTrackOption {
  final String mainTitle;
  final String? subTitle;
  final bool selected;
  final VoidCallback onSelect;

  const SettingsTrackOption({
    required this.mainTitle,
    this.subTitle,
    required this.selected,
    required this.onSelect,
  });
}

/// Settings popup shared by both theater screens: owns only page navigation,
/// with track data supplied as props. A null [audioOptions] omits the Audio
/// tile.
class TheaterSettingsMenu extends StatefulWidget {
  final String subtitlePreview;
  final List<SettingsTrackOption> subtitleOptions;
  final String? audioPreview;
  final List<SettingsTrackOption>? audioOptions;
  final VoidCallback onClose;
  final bool uiPerformanceMode;

  /// Seeds the Libass toggle row; null hides it (the ExoPlayer path has no
  /// libass).
  final bool? libassEnabled;

  /// Fired with the toggled value; `TheaterScreen._handleLibassToggle`
  /// persists it and restarts playback.
  final ValueChanged<bool>? onToggleLibass;

  const TheaterSettingsMenu({
    super.key,
    required this.subtitlePreview,
    required this.subtitleOptions,
    this.audioPreview,
    this.audioOptions,
    required this.onClose,
    this.libassEnabled,
    this.onToggleLibass,
    this.uiPerformanceMode = false,
  }) : assert(
         (libassEnabled == null) == (onToggleLibass == null),
         'libassEnabled and onToggleLibass must both be null or both be '
         'provided',
       );

  @override
  State<TheaterSettingsMenu> createState() => _TheaterSettingsMenuState();
}

class _TheaterSettingsMenuState extends State<TheaterSettingsMenu> {
  _MenuPage _currentPage = _MenuPage.main;

  bool get _hasAudio => widget.audioOptions != null;

  @override
  Widget build(BuildContext context) {
    final menuContent = Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: BoxDecoration(
        color: AppPalette.surface.withValues(
          alpha: widget.uiPerformanceMode ? 0.98 : 0.85,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: switch (_currentPage) {
            _MenuPage.main => _buildMain(),
            _MenuPage.subtitles => _buildList(widget.subtitleOptions),
            _MenuPage.audio => _buildList(widget.audioOptions ?? const []),
          },
        ),
      ),
    );

    return FrostedContainer(
      uiPerformanceMode: widget.uiPerformanceMode,
      sigma: context.appMaterials.standard,
      borderRadius: BorderRadius.circular(12),
      child: DpadRegion(
        memoryKey: 'theater.settingsMenu.${_currentPage.name}',
        child: menuContent,
      ),
    );
  }

  Widget _buildMain() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Tile(
          icon: Icons.subtitles_outlined,
          title: 'Subtitles',
          sub: widget.subtitlePreview,
          onTap: () => setState(() => _currentPage = _MenuPage.subtitles),
          autofocus: true,
        ),
        if (_hasAudio)
          _Tile(
            icon: Icons.audiotrack_outlined,
            title: 'Audio',
            sub: widget.audioPreview ?? '',
            onTap: () => setState(() => _currentPage = _MenuPage.audio),
          ),
        if (widget.onToggleLibass != null)
          _ToggleTile(
            icon: Icons.text_fields_rounded,
            // Terse to fit the popup's fixed 280px width.
            title: 'Libass Subtitles',
            value: widget.libassEnabled ?? true,
            onChanged: (v) {
              widget.onToggleLibass!(v);
              widget.onClose();
            },
          ),
      ],
    );
  }

  Widget _buildList(List<SettingsTrackOption> options) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Back(
          onTap: () => setState(() => _currentPage = _MenuPage.main),
          autofocus: true,
        ),
        const Divider(color: AppPalette.border, height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              return _TrackTile(
                mainTitle: option.mainTitle,
                subTitle: option.subTitle,
                selected: option.selected,
                onTap: () {
                  option.onSelect();
                  widget.onClose();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool autofocus;

  const _Tile({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    // Not ListTile, whose focus/tap handling would clash with DpadFocusable.
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: onTap,
      builder: (context, state, child) => Container(
        decoration: BoxDecoration(
          color: state.focused
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppPalette.white, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sub,
              style: const TextStyle(color: AppPalette.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

/// Binary toggle row: selecting it fires [onChanged] with the flipped value
/// instead of navigating.
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      onSelect: () => onChanged(!value),
      builder: (context, state, child) => Container(
        decoration: BoxDecoration(
          color: state.focused
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppPalette.white, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ToggleSwitch(value: value),
          ],
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

class _Back extends StatelessWidget {
  final VoidCallback onTap;
  final bool autofocus;

  const _Back({required this.onTap, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: onTap,
      builder: (context, state, child) => Container(
        decoration: BoxDecoration(
          color: state.focused
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: const Row(
          children: [
            Icon(Icons.arrow_back, color: AppPalette.textMuted, size: 18),
            SizedBox(width: 16),
            Text(
              'Back',
              style: TextStyle(color: AppPalette.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final String mainTitle;
  final String? subTitle;
  final bool selected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.mainTitle,
    this.subTitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      onSelect: onTap,
      builder: (context, state, child) => Container(
        decoration: BoxDecoration(
          color: state.focused
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mainTitle,
                    style: TextStyle(
                      color: selected
                          ? AppPalette.primary
                          : AppPalette.textMain,
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (subTitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subTitle!,
                      style: TextStyle(
                        color: AppPalette.textMuted.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, color: AppPalette.primary, size: 18),
          ],
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

/// Adapts media_kit's `Player` tracks into [SettingsTrackOption]s for
/// [TheaterSettingsMenu].
class DesktopTheaterSettingsMenu extends StatefulWidget {
  final Player player;
  final VoidCallback onClose;
  final bool uiPerformanceMode;

  /// Forwarded to [TheaterSettingsMenu]; `TheaterScreen` always supplies both.
  final bool? libassEnabled;
  final ValueChanged<bool>? onToggleLibass;

  const DesktopTheaterSettingsMenu({
    super.key,
    required this.player,
    required this.onClose,
    this.uiPerformanceMode = false,
    this.libassEnabled,
    this.onToggleLibass,
  });

  @override
  State<DesktopTheaterSettingsMenu> createState() =>
      _DesktopTheaterSettingsMenuState();
}

class _DesktopTheaterSettingsMenuState
    extends State<DesktopTheaterSettingsMenu> {
  late Tracks _tracks;
  AudioTrack? _activeAudio;
  SubtitleTrack? _activeSubtitle;

  late final StreamSubscription<Tracks> _tracksSub;
  late final StreamSubscription<Track> _trackSub;

  @override
  void initState() {
    super.initState();
    _tracks = widget.player.state.tracks;
    _activeAudio = widget.player.state.track.audio;
    _activeSubtitle = widget.player.state.track.subtitle;

    _tracksSub = widget.player.stream.tracks.listen((t) {
      if (mounted) setState(() => _tracks = t);
    });
    _trackSub = widget.player.stream.track.listen((t) {
      if (mounted) {
        setState(() {
          _activeAudio = t.audio;
          _activeSubtitle = t.subtitle;
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(_tracksSub.cancel());
    unawaited(_trackSub.cancel());
    super.dispose();
  }

  List<SettingsTrackOption> _subtitleOptions() {
    return _tracks.subtitle.map((t) {
      final parsed = TrackNameParser.parseSubtitle(t);
      return SettingsTrackOption(
        mainTitle: parsed.mainTitle,
        subTitle: parsed.subTitle,
        selected: t.id == _activeSubtitle?.id,
        onSelect: () => unawaited(widget.player.setSubtitleTrack(t)),
      );
    }).toList();
  }

  List<SettingsTrackOption> _audioOptions() {
    return _tracks.audio.map((t) {
      final parsed = TrackNameParser.parseAudio(
        title: t.title,
        language: t.language,
      );
      return SettingsTrackOption(
        mainTitle: parsed.mainTitle,
        subTitle: parsed.subTitle,
        selected: t.id == _activeAudio?.id,
        onSelect: () => unawaited(widget.player.setAudioTrack(t)),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final activeAudio = _activeAudio;
    return TheaterSettingsMenu(
      uiPerformanceMode: widget.uiPerformanceMode,
      onClose: widget.onClose,
      subtitlePreview: TrackNameParser.parseSubtitle(_activeSubtitle).mainTitle,
      subtitleOptions: _subtitleOptions(),
      audioPreview: activeAudio == null
          ? 'Auto'
          : TrackNameParser.parseAudio(
              title: activeAudio.title,
              language: activeAudio.language,
            ).mainTitle,
      audioOptions: _audioOptions(),
      libassEnabled: widget.libassEnabled,
      onToggleLibass: widget.onToggleLibass,
    );
  }
}
