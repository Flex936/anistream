import 'dart:async';
import 'package:anistream/features/theater/services/theater_data.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_palette.dart';

class TheaterControls extends StatefulWidget {
  final Player player;
  final VoidCallback onInteract;
  final VoidCallback onToggleSettings;

  final bool isSettingsOpen;
  final List<Chapter> chapterMetadata;

  const TheaterControls({
    super.key,
    required this.player,
    required this.onInteract,
    required this.onToggleSettings,
    required this.isSettingsOpen,
    this.chapterMetadata = const [],
  });

  @override
  State<TheaterControls> createState() => _TheaterControlsState();
}

class ChapteredTrackShape extends RoundedRectSliderTrackShape {
  final List<double> stops; // normalized 0.0–1.0, one per chapter start
  const ChapteredTrackShape({required this.stops});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    if (stops.isEmpty) return;

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final paint = Paint()..color = AppPalette.black.withValues(alpha: 0.55);
    const markWidth = 2.5;

    for (final stop in stops) {
      if (stop <= 0.01 || stop >= 0.99) continue;
      final dx = trackRect.left + stop * trackRect.width;
      context.canvas.drawRect(
        Rect.fromLTWH(
          dx - markWidth / 2,
          trackRect.top,
          markWidth,
          trackRect.height,
        ),
        paint,
      );
    }
  }
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

    _playingSub = widget.player.stream.playing.listen((v) {
      if (mounted) setState(() => _isPlaying = v);
    });
    _positionSub = widget.player.stream.position.listen((v) {
      if (mounted) setState(() => _position = v);
    });
    _durationSub = widget.player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    });
    _volumeSub = widget.player.stream.volume.listen((v) {
      if (mounted) setState(() => _volume = v);
    });
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
    // Prevent assertion errors when player initializes with 0 duration
    final maxDuration = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final currentPos = _position.inMilliseconds.toDouble().clamp(
      0.0,
      maxDuration,
    );
    final chapterStops = widget.chapterMetadata
        .map((c) => c.start.inMilliseconds / maxDuration)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderThemeData(
              trackShape: ChapteredTrackShape(stops: chapterStops),
              activeTrackColor: AppPalette.primary,
              inactiveTrackColor: AppPalette.white.withValues(alpha: 0.2),
              thumbColor: AppPalette.primary,
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              min: 0,
              max: maxDuration,
              value: currentPos,
              onChangeStart: (_) => widget.onInteract(),
              onChanged: _onSeek,
              onChangeEnd: (_) => widget.onInteract(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppPalette.white,
                size: 34,
              ),
              onPressed: () {
                _isPlaying ? widget.player.pause() : widget.player.play();
                widget.onInteract();
              },
            ),
            const SizedBox(width: 16),
            Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                _volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: AppPalette.white,
                size: 24,
              ),
              onPressed: () {
                widget.player.setVolume(_volume == 0 ? 100.0 : 0.0);
                widget.onInteract();
              },
            ),
            SizedBox(
              width: 120,
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppPalette.white,
                  inactiveTrackColor: AppPalette.white.withValues(alpha: 0.3),
                  thumbColor: AppPalette.white,
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
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
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.settings_rounded,
                color: widget.isSettingsOpen
                    ? AppPalette.primary
                    : AppPalette.white,
                size: 26,
              ),
              onPressed: widget.onToggleSettings,
            ),
          ],
        ),
      ],
    );
  }
}
