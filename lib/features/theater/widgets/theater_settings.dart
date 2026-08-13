import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/input/input_mode_scope.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../services/track_name_parser.dart';

enum _MenuPage { main, subtitles, audio }

class TheaterSettingsMenu extends StatefulWidget {
  final Player player;
  final VoidCallback onClose;
  final bool uiPerformanceMode;

  const TheaterSettingsMenu({
    super.key,
    required this.player,
    required this.onClose,
    this.uiPerformanceMode = false,
  });

  @override
  State<TheaterSettingsMenu> createState() => _TheaterSettingsMenuState();
}

class _TheaterSettingsMenuState extends State<TheaterSettingsMenu> {
  _MenuPage _currentPage = _MenuPage.main;
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

  String _getAudioPreview(AudioTrack? t) =>
      TrackNameParser.parseAudio(t).mainTitle;
  String _getSubtitlePreview(SubtitleTrack? t) =>
      TrackNameParser.parseSubtitle(t).mainTitle;

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
            _MenuPage.subtitles => _buildSubtitles(),
            _MenuPage.audio => _buildAudio(),
          },
        ),
      ),
    );

    return FrostedContainer(
      uiPerformanceMode: widget.uiPerformanceMode,
      sigma: context.appMaterials.standard,
      borderRadius: BorderRadius.circular(12),
      // DpadRegion keeps focus contained within this popup, with a
      // memoryKey so returning to the same page (main/subtitles/audio)
      // remembers where focus was, plus dpad's own beam-based traversal
      // between the rows on each page.
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
          sub: _getSubtitlePreview(_activeSubtitle),
          onTap: () => setState(() => _currentPage = _MenuPage.subtitles),
          autofocus: true,
        ),
        _Tile(
          icon: Icons.audiotrack_outlined,
          title: 'Audio',
          sub: _getAudioPreview(_activeAudio),
          onTap: () => setState(() => _currentPage = _MenuPage.audio),
        ),
      ],
    );
  }

  Widget _buildSubtitles() {
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
            itemCount: _tracks.subtitle.length,
            itemBuilder: (context, index) {
              final t = _tracks.subtitle[index];
              return _TrackTile(
                track: TrackNameParser.parseSubtitle(t),
                selected: t.id == _activeSubtitle?.id,
                onTap: () {
                  // Player.setSubtitleTrack returns a Future<void> — this
                  // onTap is a synchronous VoidCallback, so the
                  // fire-and-forget intent is made explicit instead of
                  // silently dropped (unawaited_futures).
                  unawaited(widget.player.setSubtitleTrack(t));
                  widget.onClose();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAudio() {
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
            itemCount: _tracks.audio.length,
            itemBuilder: (context, index) {
              final t = _tracks.audio[index];
              return _TrackTile(
                track: TrackNameParser.parseAudio(t),
                selected: t.id == _activeAudio?.id,
                onTap: () {
                  unawaited(widget.player.setAudioTrack(t));
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
    final dpadModeActive = context.dpadModeActive;
    return DpadFocusable(
      autofocus: autofocus && dpadModeActive,
      onSelect: onTap,
      builder: (context, state, child) => Container(
        decoration: BoxDecoration(
          color: (state.focused && dpadModeActive)
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

class _Back extends StatelessWidget {
  final VoidCallback onTap;
  final bool autofocus;

  const _Back({required this.onTap, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final dpadModeActive = context.dpadModeActive;
    return DpadFocusable(
      autofocus: autofocus && dpadModeActive,
      onSelect: onTap,
      builder: (context, state, child) => Container(
        decoration: BoxDecoration(
          color: (state.focused && dpadModeActive)
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
  final ParsedTrack track;
  final bool selected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      onSelect: onTap,
      builder: (context, state, child) => Container(
        decoration: BoxDecoration(
          color: (state.focused && context.dpadModeActive)
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
                    track.mainTitle,
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
                  if (track.subTitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      track.subTitle!,
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
