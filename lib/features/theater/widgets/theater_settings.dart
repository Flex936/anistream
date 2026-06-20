import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/theme/app_palette.dart';

enum _MenuPage { main, subtitles, audio }

class TheaterSettingsMenu extends StatefulWidget {
  final Player player;
  final VoidCallback onClose;

  const TheaterSettingsMenu({super.key, required this.player, required this.onClose});

  @override
  State<TheaterSettingsMenu> createState() => _TheaterSettingsMenuState();
}

class _TheaterSettingsMenuState extends State<TheaterSettingsMenu> {
  _MenuPage _currentPage = _MenuPage.main;
  late Tracks _tracks;
  AudioTrack? _activeAudio;
  SubtitleTrack? _activeSubtitle;

  late final StreamSubscription _tracksSub;
  late final StreamSubscription _trackSub;

  @override
  void initState() {
    super.initState();
    _tracks = widget.player.state.tracks;
    _activeAudio = widget.player.state.track.audio;
    _activeSubtitle = widget.player.state.track.subtitle;

    _tracksSub = widget.player.stream.tracks.listen((t) { if (mounted) setState(() => _tracks = t); });
    _trackSub = widget.player.stream.track.listen((t) { 
      if (mounted) setState(() { _activeAudio = t.audio; _activeSubtitle = t.subtitle; }); 
    });
  }

  @override
  void dispose() {
    _tracksSub.cancel();
    _trackSub.cancel();
    super.dispose();
  }

  String _getAudioName(AudioTrack? t) => t?.title ?? t?.language ?? 'Auto';
  String _getSubtitleName(SubtitleTrack? t) => t?.id == 'no' ? 'Disabled' : (t?.title ?? t?.language ?? 'Auto');

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 280,
          constraints: const BoxConstraints(maxHeight: 350),
          decoration: BoxDecoration(
            color: AppPalette.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: switch (_currentPage) {
              _MenuPage.main => _buildMain(),
              _MenuPage.subtitles => _buildSubtitles(),
              _MenuPage.audio => _buildAudio(),
            },
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildMain() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Tile(icon: Icons.subtitles_outlined, title: 'Subtitles', sub: _getSubtitleName(_activeSubtitle), onTap: () => setState(() => _currentPage = _MenuPage.subtitles), autofocus: true),
        _Tile(icon: Icons.audiotrack_outlined, title: 'Audio', sub: _getAudioName(_activeAudio), onTap: () => setState(() => _currentPage = _MenuPage.audio)),
      ],
    );
  }

  Widget _buildSubtitles() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Back(onTap: () => setState(() => _currentPage = _MenuPage.main), autofocus: true),
        const Divider(color: AppPalette.border, height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _tracks.subtitle.length,
            itemBuilder: (context, index) {
              final t = _tracks.subtitle[index];
              return _TrackTile(
                title: _getSubtitleName(t), 
                selected: t.id == _activeSubtitle?.id, 
                onTap: () { widget.player.setSubtitleTrack(t); widget.onClose(); }
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildAudio() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Back(onTap: () => setState(() => _currentPage = _MenuPage.main), autofocus: true),
        const Divider(color: AppPalette.border, height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _tracks.audio.length,
            itemBuilder: (context, index) {
              final t = _tracks.audio[index];
              return _TrackTile(
                title: _getAudioName(t), 
                selected: t.id == _activeAudio?.id, 
                onTap: () { widget.player.setAudioTrack(t); widget.onClose(); }
              );
            },
          ),
        )
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon; final String title; final String sub; final VoidCallback onTap; final bool autofocus;
  const _Tile({required this.icon, required this.title, required this.sub, required this.onTap, this.autofocus = false});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      autofocus: autofocus,
      focusColor: AppPalette.white.withValues(alpha: 0.1),
      hoverColor: AppPalette.white.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, color: AppPalette.white, size: 20),
      title: Text(title, style: const TextStyle(color: AppPalette.textMain, fontSize: 14)),
      trailing: Text(sub, style: const TextStyle(color: AppPalette.textMuted, fontSize: 12)),
      onTap: onTap,
    );
  }
}

class _Back extends StatelessWidget {
  final VoidCallback onTap; final bool autofocus;
  const _Back({required this.onTap, this.autofocus = false});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      autofocus: autofocus,
      focusColor: AppPalette.white.withValues(alpha: 0.1),
      hoverColor: AppPalette.white.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: const Icon(Icons.arrow_back, color: AppPalette.textMuted, size: 18),
      title: const Text('Back', style: TextStyle(color: AppPalette.textMuted, fontSize: 14)),
      onTap: onTap,
    );
  }
}

class _TrackTile extends StatelessWidget {
  final String title; final bool selected; final VoidCallback onTap;
  const _TrackTile({required this.title, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      focusColor: AppPalette.white.withValues(alpha: 0.1),
      hoverColor: AppPalette.white.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(title, style: TextStyle(color: selected ? AppPalette.primary : AppPalette.textMain, fontSize: 14)),
      trailing: selected ? const Icon(Icons.check, color: AppPalette.primary, size: 18) : null,
      onTap: onTap,
    );
  }
}