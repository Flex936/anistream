import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../theme/app_palette.dart';

class TheaterControls extends StatefulWidget {
  final Player player;
  final VoidCallback onInteract;
  final VoidCallback onToggleSettings;
  final bool isSettingsOpen;

  const TheaterControls({
    super.key,
    required this.player,
    required this.onInteract,
    required this.onToggleSettings,
    required this.isSettingsOpen,
  });

  @override
  State<TheaterControls> createState() => _TheaterControlsState();
}

class _TheaterControlsState extends State<TheaterControls> {
  bool _isPlaying = false;
  double _volume = 100.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late final StreamSubscription _playingSub;
  late final StreamSubscription _positionSub;
  late final StreamSubscription _durationSub;
  late final StreamSubscription _volumeSub;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _volume = widget.player.state.volume;

    _playingSub = widget.player.stream.playing.listen((v) => setState(() => _isPlaying = v));
    _positionSub = widget.player.stream.position.listen((v) => setState(() => _position = v));
    _durationSub = widget.player.stream.duration.listen((v) => setState(() => _duration = v));
    _volumeSub = widget.player.stream.volume.listen((v) => setState(() => _volume = v));
  }

  @override
  void dispose() {
    _playingSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _volumeSub.cancel();
    super.dispose();
  }

  void _onSeek(double value) {
    widget.player.seek(Duration(milliseconds: value.toInt()));
    widget.onInteract();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Timeline Scrubber ──
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppPalette.primary,
              inactiveTrackColor: AppPalette.white.withValues(alpha: 0.2),
              thumbColor: AppPalette.primary,
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              min: 0,
              max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1,
              value: _position.inMilliseconds.toDouble().clamp(
                    0,
                    _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1,
                  ),
              onChangeStart: (_) => widget.onInteract(),
              onChanged: _onSeek,
              onChangeEnd: (_) => widget.onInteract(),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Controls Row ──
        Row(
          children: [
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppPalette.white, size: 34),
              onPressed: () {
                _isPlaying ? widget.player.pause() : widget.player.play();
                widget.onInteract();
              },
            ),
            const SizedBox(width: 16),
            Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: const TextStyle(color: AppPalette.textMain, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(_volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: AppPalette.white, size: 24),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppPalette.white,
                  inactiveTrackColor: AppPalette.white.withValues(alpha: 0.3),
                  thumbColor: AppPalette.white,
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  min: 0,
                  max: 100,
                  value: _volume.clamp(0.0, 100.0),
                  onChanged: (v) {
                    widget.player.setVolume(v);
                    widget.onInteract();
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(Icons.settings_rounded, color: widget.isSettingsOpen ? AppPalette.primary : AppPalette.white, size: 26),
              onPressed: widget.onToggleSettings,
            ),
          ],
        ),
      ],
    );
  }
}