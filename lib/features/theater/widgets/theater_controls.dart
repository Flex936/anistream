import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../services/theater_data.dart';
import 'seekbar.dart';

class TheaterControls extends StatefulWidget {
  final Player player;

  /// Discrete-interaction ping — a button press, a slider value tick, the
  /// skip-chip tap. Resets the auto-hide countdown without suspending it.
  final VoidCallback onInteract;

  /// Continuous-interaction brackets — fired at the start/end of a
  /// seekbar or volume-slider drag. Suspends the auto-hide countdown for
  /// the full duration of the drag rather than relying on the drag's own
  /// per-update callback (`onInteract`, above) to keep re-pinging it
  /// often enough on its own.
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  final VoidCallback onToggleSettings;
  final VoidCallback onToggleFullscreen;

  /// Fixed 90-second forward seek for OP/ED skipping — the button this
  /// wires up is the Mobile/TV-reachable equivalent of desktop's Ctrl+→
  /// shortcut (`TheaterScreen._onKeyEvent`/`_exactSkipForward`, which
  /// this same callback also is). Always required, unlike
  /// `onToggleFullscreen` — every platform gets this control, just via a
  /// button instead of a keyboard chord on Mobile/TV.
  final VoidCallback onExactSkip;

  final bool isSettingsOpen;
  final bool isFullscreen;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;
  final bool dpadModeActive;

  /// True only on Windows/Linux/macOS. Gates the fullscreen toggle per
  /// DESIGN.md § 3 ("Hide PC-specific UI controls ... on Mobile/TV
  /// builds") — Mobile has no windowed state to escape, and TV is
  /// already permanently fullscreen, so there's no reachable "windowed"
  /// counterpart for the button to toggle back to on either platform.
  /// Also used to vary the exact-skip button's tooltip, since Ctrl+→ is
  /// only ever reachable on this platform.
  final bool isDesktop;

  /// Reports whether Seekbar/the volume slider currently holds keyboard
  /// focus, up to `theater_screen.dart`'s global keyboard dispatcher — so
  /// it can defer to that widget's own local Left/Right handling instead
  /// of double-seeking or unexpectedly seeking while the user is nudging
  /// volume. Both optional: nothing breaks if a caller doesn't care.
  final ValueChanged<bool>? onSeekbarFocusChange;
  final ValueChanged<bool>? onVolumeFocusChange;

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
    this.uiPerformanceMode = false,
    this.dpadModeActive = false,
    this.chapterMetadata = const [],
    this.onSeekbarFocusChange,
    this.onVolumeFocusChange,
  });

  @override
  State<TheaterControls> createState() => _TheaterControlsState();
}

// Rebuild isolation: this State owns only _isPlaying and _volume, both of
// which change on discrete user actions (a play/pause press, a volume
// drag), not continuously. _PlaybackTimeline and _PlaybackTimeLabel below
// are separate StatefulWidgets with their own State objects and stream
// subscriptions for the fields that tick several times a second
// (position/duration/buffer). Widget rebuilds only ever propagate down
// from whichever State calls setState, so isolating the ticking fields
// into their own State objects means a position tick only rebuilds those
// two small subtrees, not the play button, volume slider, or settings/
// fullscreen buttons alongside them in this Row.
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
          // Owns _position/_duration/_buffer and the skip-chip/Seekbar
          // visuals that depend on them, ticking in isolation.
          // dpadModeActive flows through to Seekbar, which keeps its own
          // Focus-based key handling — see seekbar.dart.
          _PlaybackTimeline(
            player: widget.player,
            chapterMetadata: widget.chapterMetadata,
            uiPerformanceMode: widget.uiPerformanceMode,
            dpadModeActive: widget.dpadModeActive,
            onInteract: widget.onInteract,
            onInteractionStart: widget.onInteractionStart,
            onInteractionEnd: widget.onInteractionEnd,
            onSeekbarFocusChange: widget.onSeekbarFocusChange,
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
                // The sensible default D-Pad landing spot the first time
                // the control bar appears — matches "one autofocus per
                // screen." Harmless on re-shows too: DpadRegion's
                // memoryKey on the wrapping region in theater_screen.dart
                // restores whatever was last focused instead.
                autofocus: true,
                onPressed: () {
                  // Player.pause()/play() return Future<void> — onPressed
                  // is a synchronous VoidCallback, so the fire-and-forget
                  // intent is made explicit (unawaited_futures).
                  unawaited(
                    _isPlaying ? widget.player.pause() : widget.player.play(),
                  );
                  widget.onInteract();
                },
              ),
              const SizedBox(width: 16),

              // Owns its own position/duration subscription, renders just
              // the "00:00 / 00:00" text. Ticks in isolation.
              _PlaybackTimeLabel(player: widget.player),
              const SizedBox(width: 16),

              // Fixed-duration OP/ED skip — Mobile/TV's reachable
              // equivalent of desktop's Ctrl+→ shortcut (both call the
              // same TheaterScreen._exactSkipForward via this one
              // callback). Placed here, ahead of the trailing Spacer,
              // rather than alongside the mute/settings/fullscreen
              // cluster on the right — keeps this cluster's own fixed
              // 44dp targets from getting any more crowded.
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
                  // Not const: inactiveTrackColor calls
                  // AppPalette.white.withValues(alpha: 0.3), a method
                  // invocation the compiler rejects in a const expression
                  // (const_eval_method_invocation). Only the two shape
                  // constructors below (no method calls in their
                  // arguments) can be const.
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
                  // Left as a plain Material Slider — it already has its
                  // own working keyboard-arrow-when-focused behavior as a
                  // standard Flutter form control, the same reasoning as
                  // Seekbar: a plain Focus-participating widget that
                  // interops with dpad's traversal without needing
                  // DpadFocusable wrapping. Given an explicit focusNode so
                  // this State can observe its focus state and report it
                  // upstream via onVolumeFocusChange. onChangeStart/End
                  // bracket a drag the same way Seekbar's onSeekStart/End
                  // do.
                  child: Slider(
                    focusNode: _volumeFocusNode,
                    max: 100,
                    value: _volume.clamp(0.0, 100.0),
                    onChanged: (v) {
                      // _handleVolumeChanged is Future<void> — onChanged
                      // is a synchronous callback, so wrapping makes the
                      // fire-and-forget intent explicit.
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

              // Desktop-only per DESIGN.md § 3 — Mobile has no windowed
              // state for this button to toggle back out of, and TV is
              // permanently fullscreen.
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

/// Owns [Player.stream.position]/[duration]/[buffer] and renders the
/// skip-chip + [Seekbar] — the parts of the control bar that redraw
/// every tick. Kept separate from [_TheaterControlsState] so its
/// setState() calls only rebuild this subtree, not the play/volume/
/// settings buttons alongside it in the parent's Row.
class _PlaybackTimeline extends StatefulWidget {
  final Player player;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;
  final bool dpadModeActive;
  final VoidCallback onInteract;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<bool>? onSeekbarFocusChange;

  const _PlaybackTimeline({
    required this.player,
    required this.chapterMetadata,
    required this.uiPerformanceMode,
    required this.dpadModeActive,
    required this.onInteract,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    this.onSeekbarFocusChange,
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
    // Player.seek returns Future<void> — this is wired to Seekbar's
    // synchronous onSeek callback, so the fire-and-forget intent is made
    // explicit (unawaited_futures). Fires on every drag update, not just
    // start/end, so it's mapped to onInteract (not onInteractionStart/
    // End): it's a per-tick ping, and
    // ControlsVisibilityController.registerActivity() already no-ops the
    // timer schedule while an interaction is in progress, so this can't
    // fight with the explicit begin/end bracket below.
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

  @override
  Widget build(BuildContext context) {
    final skipTarget = _activeSkipChapter;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: AnimatedOpacity(
            opacity: skipTarget != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedSlide(
              offset: skipTarget != null ? Offset.zero : const Offset(0, 0.5),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: IgnorePointer(
                ignoring: skipTarget == null,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Material(
                    color: AppPalette.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (skipTarget != null) {
                          unawaited(widget.player.seek(skipTarget.end));
                          widget.onInteract();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              skipTarget?.skipLabel ?? 'Skip',
                              style: const TextStyle(
                                color: AppPalette.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.skip_next_rounded,
                              color: AppPalette.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        Seekbar(
          position: _position,
          duration: _duration,
          buffer: _buffer,
          chapters: widget.chapterMetadata,
          uiPerformanceMode: widget.uiPerformanceMode,
          dpadModeActive: widget.dpadModeActive,
          onSeek: _onSeek,
          onSeekStart: widget.onInteractionStart,
          onSeekEnd: widget.onInteractionEnd,
          onFocusChange: widget.onSeekbarFocusChange,
        ),
      ],
    );
  }
}

/// Owns its own (duplicate, but cheap — the stream is broadcast)
/// subscription to [Player.stream.position]/[duration] and renders just
/// the "00:00 / 00:00" label. Kept as a separate State from
/// [_PlaybackTimeline] so the label — which sits in the parent's icon
/// Row, not inside the timeline's Column — ticks independently without
/// either widget reaching into the other's state.
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

/// Small reusable icon button for the control bar. state.focused drives
/// the ring directly, with no local state to manage, so this is a
/// StatelessWidget.
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
