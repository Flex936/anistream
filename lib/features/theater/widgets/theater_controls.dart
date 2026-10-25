import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../services/theater_data.dart';
import 'playback_action_chip.dart';
import 'seekbar.dart';
import 'skip_chip.dart';

class TheaterControls extends StatefulWidget {
  final Player player;

  /// Discrete-interaction ping (button press, slider tick); restarts the
  /// auto-hide countdown.
  final VoidCallback onInteract;

  /// Brackets a seekbar or volume-slider drag, suspending auto-hide throughout.
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  final VoidCallback onToggleSettings;
  final VoidCallback onToggleFullscreen;

  /// Fixed 90 s forward seek for skipping an OP/ED; the button equivalent of
  /// desktop's Ctrl+→ (`TheaterScreen._exactSkipForward`).
  final VoidCallback onExactSkip;

  final bool isSettingsOpen;
  final bool isFullscreen;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;
  final bool isTvPlatform;

  /// True on Windows/Linux/macOS; gates the fullscreen toggle and the
  /// Ctrl+→ hint in the skip tooltip.
  final bool isDesktop;

  /// Reports Seekbar/volume-slider focus so the screen's global key handler
  /// can defer to them.
  final ValueChanged<bool>? onSeekbarFocusChange;
  final ValueChanged<bool>? onVolumeFocusChange;

  /// False once `episode >= totalEpisodes`; hides the Next Episode chip.
  final bool hasNextEpisode;

  /// Fired by the Next Episode chip; see
  /// `TheaterScreen._requestNextEpisodeTransition`.
  final VoidCallback onNextEpisode;

  const TheaterControls({
    super.key,
    required this.player,
    required this.onInteract,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onToggleSettings,
    required this.onToggleFullscreen,
    required this.onExactSkip,
    required this.isSettingsOpen,
    required this.isFullscreen,
    required this.isDesktop,
    required this.hasNextEpisode,
    required this.onNextEpisode,
    this.uiPerformanceMode = false,
    this.isTvPlatform = false,
    this.chapterMetadata = const [],
    this.onSeekbarFocusChange,
    this.onVolumeFocusChange,
  });

  @override
  State<TheaterControls> createState() => _TheaterControlsState();
}

class _TheaterControlsState extends State<TheaterControls> {
  bool _isPlaying = false;
  double _volume = 100.0;

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<double> _volumeSub;

  late final FocusNode _volumeFocusNode;

  final _prefs = SharedPreferencesAsync();

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.player.state.playing;
    _volume = widget.player.state.volume;

    _playingSub = widget.player.stream.playing.listen((v) {
      if (mounted) setState(() => _isPlaying = v);
    });
    _volumeSub = widget.player.stream.volume.listen((v) {
      if (mounted) setState(() => _volume = v);
    });

    _volumeFocusNode = FocusNode(debugLabel: 'TheaterVolumeSlider')
      ..addListener(_handleVolumeFocusChange);
  }

  @override
  void dispose() {
    unawaited(_playingSub.cancel());
    unawaited(_volumeSub.cancel());
    _volumeFocusNode.removeListener(_handleVolumeFocusChange);
    _volumeFocusNode.dispose();
    super.dispose();
  }

  void _handleVolumeFocusChange() {
    widget.onVolumeFocusChange?.call(_volumeFocusNode.hasFocus);
  }

  Future<void> _handleVolumeChanged(double value) async {
    await widget.player.setVolume(value);
    if (value > 0) {
      await _prefs.setDouble('theater_volume', value);
    }
  }

  Future<void> _toggleMute() async {
    if (widget.player.state.volume == 0) {
      double savedVolume = await _prefs.getDouble('theater_volume') ?? 100.0;
      if (savedVolume == 0) savedVolume = 100.0;
      await widget.player.setVolume(savedVolume);
    } else {
      await _prefs.setDouble('theater_volume', widget.player.state.volume);
      await widget.player.setVolume(0.0);
    }
    widget.onInteract();
  }

  @override
  Widget build(BuildContext context) {
    final coreControls = Container(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
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
          _PlaybackTimeline(
            player: widget.player,
            chapterMetadata: widget.chapterMetadata,
            uiPerformanceMode: widget.uiPerformanceMode,
            isTvPlatform: widget.isTvPlatform,
            onInteract: widget.onInteract,
            onInteractionStart: widget.onInteractionStart,
            onInteractionEnd: widget.onInteractionEnd,
            onSeekbarFocusChange: widget.onSeekbarFocusChange,
            hasNextEpisode: widget.hasNextEpisode,
            onNextEpisode: widget.onNextEpisode,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              _TheaterIconButton(
                icon: _isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: _isPlaying ? 'Pause' : 'Play',
                size: 34,
                // See DESIGN.md § 4.
                autofocus: true,
                onPressed: () {
                  unawaited(
                    _isPlaying ? widget.player.pause() : widget.player.play(),
                  );
                  widget.onInteract();
                },
              ),
              const SizedBox(width: 16),

              _PlaybackTimeLabel(player: widget.player),
              const SizedBox(width: 16),

              // Left of the Spacer to keep the right-hand cluster uncrowded.
              _TheaterIconButton(
                icon: Icons.fast_forward_rounded,
                tooltip: widget.isDesktop ? 'Skip 1:30 (Ctrl+→)' : 'Skip 1:30',
                onPressed: widget.onExactSkip,
              ),

              const Spacer(),
              _TheaterIconButton(
                icon: _volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                tooltip: _volume == 0 ? 'Unmute' : 'Mute',
                onPressed: _toggleMute,
              ),
              SizedBox(
                width: (MediaQuery.sizeOf(context).width * 0.12).clamp(
                  70.0,
                  120.0,
                ),
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
                  // A plain Slider handles arrow keys and interops with dpad
                  // traversal. The explicit focusNode lets this State report
                  // focus upstream.
                  child: Slider(
                    focusNode: _volumeFocusNode,
                    max: 100,
                    value: _volume.clamp(0.0, 100.0),
                    onChanged: (v) {
                      unawaited(_handleVolumeChanged(v));
                      widget.onInteract();
                    },
                    onChangeStart: (_) => widget.onInteractionStart(),
                    onChangeEnd: (_) => widget.onInteractionEnd(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _TheaterIconButton(
                icon: Icons.settings_rounded,
                tooltip: 'Settings',
                color: widget.isSettingsOpen
                    ? AppPalette.primary
                    : AppPalette.white,
                onPressed: widget.onToggleSettings,
              ),

              // See DESIGN.md § 3.
              if (widget.isDesktop)
                _TheaterIconButton(
                  icon: widget.isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  tooltip: widget.isFullscreen
                      ? 'Exit Fullscreen'
                      : 'Fullscreen',
                  size: 28,
                  onPressed: widget.onToggleFullscreen,
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

/// Per-tick subtree: the skip/next chip and [Seekbar], with their own
/// position, duration and buffer subscriptions. See ARCHITECTURE.md § 3.
class _PlaybackTimeline extends StatefulWidget {
  final Player player;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;
  final bool isTvPlatform;
  final VoidCallback onInteract;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<bool>? onSeekbarFocusChange;
  final bool hasNextEpisode;
  final VoidCallback onNextEpisode;

  const _PlaybackTimeline({
    required this.player,
    required this.chapterMetadata,
    required this.uiPerformanceMode,
    required this.isTvPlatform,
    required this.onInteract,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    this.onSeekbarFocusChange,
    required this.hasNextEpisode,
    required this.onNextEpisode,
  });

  @override
  State<_PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<_PlaybackTimeline> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<Duration> _bufferSub;

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _buffer = widget.player.state.buffer;

    _positionSub = widget.player.stream.position.listen((v) {
      if (mounted) setState(() => _position = v);
    });
    _durationSub = widget.player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    });
    _bufferSub = widget.player.stream.buffer.listen((v) {
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
    // Fires on every drag update, so it pings onInteract; registerActivity()
    // skips arming the hide timer while a drag is in progress.
    unawaited(widget.player.seek(time));
    widget.onInteract();
  }

  Chapter? get _activeSkipChapter {
    for (final c in widget.chapterMetadata) {
      if (c.isSkippable &&
          _position >= c.start &&
          _position < (c.end - const Duration(seconds: 1))) {
        return c;
      }
    }
    return null;
  }

  // Above NextEpisodePrefetchController's 0.85 arm threshold, so prefetch
  // starts first.
  static const double _kNextEpisodeChipThreshold = 0.95;

  // Mutually exclusive with the skip chip: both share one slot in build().
  bool get _showNextEpisodeChip {
    if (!widget.hasNextEpisode) return false;
    if (_activeSkipChapter != null) return false;
    if (_duration <= Duration.zero) return false;
    return (_position.inMilliseconds / _duration.inMilliseconds) >=
        _kNextEpisodeChipThreshold;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _showNextEpisodeChip
              ? PlaybackActionChip(
                  visible: true,
                  label: 'Next Episode',
                  onTap: widget.onNextEpisode,
                )
              : SkipChip(
                  chapters: widget.chapterMetadata,
                  position: _position,
                  onSkip: (target) {
                    unawaited(widget.player.seek(target));
                    widget.onInteract();
                  },
                ),
        ),
        Seekbar(
          position: _position,
          duration: _duration,
          buffer: _buffer,
          chapters: widget.chapterMetadata,
          uiPerformanceMode: widget.uiPerformanceMode,
          isTvPlatform: widget.isTvPlatform,
          onSeek: _onSeek,
          onSeekStart: widget.onInteractionStart,
          onSeekEnd: widget.onInteractionEnd,
          onFocusChange: widget.onSeekbarFocusChange,
        ),
      ],
    );
  }
}

/// The "00:00 / 00:00" label, subscribed to position and duration itself so
/// it ticks apart from [_PlaybackTimeline].
class _PlaybackTimeLabel extends StatefulWidget {
  final Player player;
  const _PlaybackTimeLabel({required this.player});

  @override
  State<_PlaybackTimeLabel> createState() => _PlaybackTimeLabelState();
}

class _PlaybackTimeLabelState extends State<_PlaybackTimeLabel> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;

    _positionSub = widget.player.stream.position.listen((v) {
      if (mounted) setState(() => _position = v);
    });
    _durationSub = widget.player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    });
  }

  @override
  void dispose() {
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
      style: const TextStyle(
        color: AppPalette.textMain,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Control-bar icon button; `state.focused` drives the focus ring.
class _TheaterIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final String tooltip;
  final VoidCallback onPressed;
  final bool autofocus;

  const _TheaterIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color = AppPalette.white,
    this.size = 26,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DpadFocusable(
        autofocus: autofocus,
        onSelect: onPressed,
        builder: (context, state, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: state.focused
                  ? AppPalette.primary
                  : AppPalette.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: size),
        ),
        child: const SizedBox.shrink(),
      ),
    );
  }
}
