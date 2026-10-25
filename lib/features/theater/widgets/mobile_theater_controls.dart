import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../services/playback_handle.dart';
import '../services/theater_data.dart';
import 'seekbar.dart';
import 'skip_chip.dart';

/// Touch-oriented control bar for `ExoTheaterScreen` and for `TheaterScreen`
/// on non-desktop platforms, driven by a [PlaybackHandle]. Has no D-pad
/// focus wiring.
class MobileTheaterControls extends StatefulWidget {
  final PlaybackHandle playback;
  final VoidCallback onInteract;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  /// Null hides the settings button (nothing to open yet).
  final VoidCallback? onToggleSettings;
  final bool isSettingsOpen;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;

  /// Reports Seekbar focus so the screen's global key handler can defer to it.
  final ValueChanged<bool>? onSeekbarFocusChange;

  const MobileTheaterControls({
    super.key,
    required this.playback,
    required this.onInteract,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    this.onToggleSettings,
    this.isSettingsOpen = false,
    this.chapterMetadata = const [],
    this.uiPerformanceMode = false,
    this.onSeekbarFocusChange,
  });

  @override
  State<MobileTheaterControls> createState() => _MobileTheaterControlsState();
}

class _MobileTheaterControlsState extends State<MobileTheaterControls> {
  bool _isPlaying = false;
  double _volume = 100.0;

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<double> _volumeSub;

  final _prefs = SharedPreferencesAsync();

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.playback.isPlaying;
    _volume = widget.playback.volume;

    _playingSub = widget.playback.playingStream.listen((v) {
      if (mounted) setState(() => _isPlaying = v);
    });
    _volumeSub = widget.playback.volumeStream.listen((v) {
      if (mounted) setState(() => _volume = v);
    });
  }

  @override
  void dispose() {
    unawaited(_playingSub.cancel());
    unawaited(_volumeSub.cancel());
    super.dispose();
  }

  // Shares the 'theater_volume' key with TheaterControls.
  Future<void> _toggleMute() async {
    if (widget.playback.volume == 0) {
      double savedVolume = await _prefs.getDouble('theater_volume') ?? 100.0;
      if (savedVolume == 0) savedVolume = 100.0;
      await widget.playback.setVolume(savedVolume);
    } else {
      await _prefs.setDouble('theater_volume', widget.playback.volume);
      await widget.playback.setVolume(0.0);
    }
    widget.onInteract();
  }

  // Reads position/duration at tap time; subscribing would rebuild this State
  // every tick. Clamping matches `ExoTheaterScreen._seekBy`.
  void _seekBy(Duration delta) {
    final target = widget.playback.position + delta;
    final duration = widget.playback.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    unawaited(widget.playback.seek(clamped));
    widget.onInteract();
  }

  @override
  Widget build(BuildContext context) {
    final coreControls = Container(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppPalette.base.withValues(
              alpha: widget.uiPerformanceMode ? 0.98 : 0.95,
            ),
            AppPalette.base.withValues(
              alpha: widget.uiPerformanceMode ? 0.8 : 0.4,
            ),
            AppPalette.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobilePlaybackTimeline(
            playback: widget.playback,
            chapterMetadata: widget.chapterMetadata,
            uiPerformanceMode: widget.uiPerformanceMode,
            onInteract: widget.onInteract,
            onInteractionStart: widget.onInteractionStart,
            onInteractionEnd: widget.onInteractionEnd,
            onSeekbarFocusChange: widget.onSeekbarFocusChange,
          ),
          const SizedBox(height: 8),
          // Equal-flex side regions keep the skip/play group centered whether
          // or not settings is shown.
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _MobileIconButton(
                    icon: _volume == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    onPressed: _toggleMute,
                  ),
                ),
              ),
              _MobileIconButton(
                icon: Icons.replay_10_rounded,
                onPressed: () => _seekBy(const Duration(seconds: -10)),
              ),
              const SizedBox(width: 20),
              _MobileIconButton(
                icon: _isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 30,
                onPressed: () {
                  unawaited(widget.playback.playOrPause());
                  widget.onInteract();
                },
              ),
              const SizedBox(width: 20),
              _MobileIconButton(
                icon: Icons.forward_10_rounded,
                onPressed: () => _seekBy(const Duration(seconds: 10)),
              ),
              Expanded(
                child: widget.onToggleSettings == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: _MobileIconButton(
                          icon: Icons.settings_rounded,
                          color: widget.isSettingsOpen
                              ? AppPalette.primary
                              : AppPalette.white,
                          onPressed: widget.onToggleSettings!,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.uiPerformanceMode) {
      return coreControls;
    }

    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppPalette.transparent, AppPalette.black, AppPalette.black],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: FrostedContainer(
        uiPerformanceMode: false,
        sigma: context.appMaterials.prominent,
        child: coreControls,
      ),
    );
  }
}

/// Per-tick subtree: skip chip, [Seekbar], and time label.
class _MobilePlaybackTimeline extends StatefulWidget {
  final PlaybackHandle playback;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;
  final VoidCallback onInteract;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<bool>? onSeekbarFocusChange;

  const _MobilePlaybackTimeline({
    required this.playback,
    required this.chapterMetadata,
    required this.uiPerformanceMode,
    required this.onInteract,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    this.onSeekbarFocusChange,
  });

  @override
  State<_MobilePlaybackTimeline> createState() =>
      _MobilePlaybackTimelineState();
}

class _MobilePlaybackTimelineState extends State<_MobilePlaybackTimeline> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<Duration> _bufferSub;

  @override
  void initState() {
    super.initState();
    _position = widget.playback.position;
    _duration = widget.playback.duration;
    _buffer = widget.playback.buffer;

    _positionSub = widget.playback.positionStream.listen((v) {
      if (mounted) setState(() => _position = v);
    });
    _durationSub = widget.playback.durationStream.listen((v) {
      if (mounted) setState(() => _duration = v);
    });
    _bufferSub = widget.playback.bufferStream.listen((v) {
      if (mounted) setState(() => _buffer = v);
    });
  }

  @override
  void dispose() {
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    unawaited(_bufferSub.cancel());
    super.dispose();
  }

  void _onSeek(Duration time) {
    unawaited(widget.playback.seek(time));
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
        SkipChip(
          chapters: widget.chapterMetadata,
          position: _position,
          onSkip: (target) {
            unawaited(widget.playback.seek(target));
            widget.onInteract();
          },
        ),
        Seekbar(
          position: _position,
          duration: _duration,
          buffer: _buffer,
          chapters: widget.chapterMetadata,
          uiPerformanceMode: widget.uiPerformanceMode,
          onSeek: _onSeek,
          onSeekStart: widget.onInteractionStart,
          onSeekEnd: widget.onInteractionEnd,
          onFocusChange: widget.onSeekbarFocusChange,
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
          style: const TextStyle(
            color: AppPalette.textMain,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Plain `IconButton` with a 48x48 minimum touch target; see DESIGN.md § 3.
class _MobileIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final double size;

  const _MobileIconButton({
    required this.icon,
    required this.onPressed,
    this.color = AppPalette.white,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: size),
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }
}
