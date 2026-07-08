// lib/features/theater/widgets/theater_controls.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../services/theater_data.dart';
import 'seekbar.dart';

class TheaterControls extends StatefulWidget {
  final Player player;
  final VoidCallback onInteract;
  final VoidCallback onToggleSettings;
  final VoidCallback onToggleFullscreen;
  final bool isSettingsOpen;
  final bool isFullscreen;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;
  final bool dpadModeActive;
  final VoidCallback onPip;

  const TheaterControls({
    super.key,
    required this.player,
    required this.onInteract,
    required this.onToggleSettings,
    required this.onToggleFullscreen,
    required this.isSettingsOpen,
    required this.isFullscreen,
    required this.onPip,
    this.uiPerformanceMode = false,
    this.dpadModeActive = false,
    this.chapterMetadata = const [],
  });

  @override
  State<TheaterControls> createState() => _TheaterControlsState();
}

class _TheaterControlsState extends State<TheaterControls> {
  bool _isPlaying = false;
  double _volume = 100.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  late final StreamSubscription _playingSub;
  late final StreamSubscription _positionSub;
  late final StreamSubscription _durationSub;
  late final StreamSubscription _volumeSub;
  late final StreamSubscription _bufferSub;

  final _prefs = SharedPreferencesAsync();

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _volume = widget.player.state.volume;
    _buffer = widget.player.state.buffer;

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
    _bufferSub = widget.player.stream.buffer.listen((v) {
      if (mounted) setState(() => _buffer = v);
    });
  }

  @override
  void dispose() {
    _playingSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _volumeSub.cancel();
    _bufferSub.cancel();
    super.dispose();
  }

  void _onSeek(Duration time) {
    widget.player.seek(time);
    widget.onInteract();
  }

  Future<void> _handleVolumeChanged(double value) async {
    widget.player.setVolume(value);
    if (value > 0) {
      await _prefs.setDouble('theater_volume', value);
    }
  }

  Future<void> _toggleMute() async {
    if (widget.player.state.volume == 0) {
      double savedVolume = await _prefs.getDouble('theater_volume') ?? 100.0;
      if (savedVolume == 0) savedVolume = 100.0;
      widget.player.setVolume(savedVolume);
    } else {
      await _prefs.setDouble('theater_volume', widget.player.state.volume);
      widget.player.setVolume(0.0);
    }
    widget.onInteract();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
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
                            widget.player.seek(skipTarget.end);
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
            onSeekStart: widget.onInteract,
            onSeekEnd: widget.onInteract,
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
                dpadModeActive: widget.dpadModeActive,
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
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              _TheaterIconButton(
                icon: _volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                tooltip: _volume == 0 ? 'Unmute' : 'Mute',
                dpadModeActive: widget.dpadModeActive,
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
                  child: Slider(
                    min: 0,
                    max: 100,
                    value: _volume.clamp(0.0, 100.0),
                    onChanged: (v) {
                      _handleVolumeChanged(v);
                      widget.onInteract();
                    },
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
                dpadModeActive: widget.dpadModeActive,
                onPressed: widget.onToggleSettings,
              ),

              if (Platform.isMacOS || Platform.isLinux)
                _TheaterIconButton(
                  icon: Icons.picture_in_picture,
                  tooltip: 'Picture in Picture',
                  dpadModeActive: widget.dpadModeActive,
                  onPressed: widget.onPip,
                ),

              _TheaterIconButton(
                icon: widget.isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                tooltip: widget.isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                size: 28,
                dpadModeActive: widget.dpadModeActive,
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
        sigma: 30,
        child: coreControls,
      ),
    );
  }
}

/// Small reusable icon button for the control bar. Wraps a plain
/// [IconButton] — keeping Flutter's normal single FocusNode, ink, and
/// tap-target behavior, with no extra phantom Focus node added to the
/// traversal chain — and layers on a ring that's only ever painted while
/// [dpadModeActive] is true, so PC/mobile pointer users never see a
/// TV-style outline flash onto a button they merely tabbed past.
class _TheaterIconButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final String tooltip;
  final VoidCallback onPressed;
  final bool dpadModeActive;

  const _TheaterIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.dpadModeActive,
    this.color = AppPalette.white,
    this.size = 26,
  });

  @override
  State<_TheaterIconButton> createState() => _TheaterIconButtonState();
}

class _TheaterIconButtonState extends State<_TheaterIconButton> {
  bool _focused = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showRing = _focused && widget.dpadModeActive;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: showRing ? AppPalette.primary : AppPalette.transparent,
          width: 2,
        ),
      ),
      child: IconButton(
        focusNode: _focusNode, // ── We pass our custom FocusNode here ──
        icon: Icon(widget.icon, color: widget.color, size: widget.size),
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        // ── IconButton's own subtle Material overlay (hover/focus tint) is
        // left as-is on every platform — that's a reasonable minimal
        // affordance for plain keyboard-Tab users on desktop. Only the
        // explicit ring above is gated to D-Pad mode, so a desktop user
        // tabbing through never sees the loud TV-style outline; a TV user
        // gets both. ──
      ),
    );
  }
}
