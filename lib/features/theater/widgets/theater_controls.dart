import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_palette.dart';
import '../services/theater_data.dart';

class TheaterControls extends StatefulWidget {
  final Player player;
  final VoidCallback onInteract;
  final VoidCallback onToggleSettings;
  final VoidCallback onToggleFullscreen;
  final bool isSettingsOpen;
  final bool isFullscreen;
  final List<Chapter> chapterMetadata;
  final bool uiPerformanceMode;

  const TheaterControls({
    super.key,
    required this.player,
    required this.onInteract,
    required this.onToggleSettings,
    required this.onToggleFullscreen,
    required this.isSettingsOpen,
    required this.isFullscreen,
    this.uiPerformanceMode = false,
    this.chapterMetadata = const [],
  });

  @override
  State<TheaterControls> createState() => _TheaterControlsState();
}

class ChapteredTrackShape extends RoundedRectSliderTrackShape {
  final List<double> stops;
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

    final paint = Paint()..color = AppPalette.base.withValues(alpha: 0.95);
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

  void _onSeek(Duration time) {
    widget.player.seek(time);
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
          // ── Skip Button Popup ──
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

          // ── Custom Seekbar ──
          _PremiumSeekbar(
            position: _position,
            duration: _duration,
            chapters: widget.chapterMetadata,
            uiPerformanceMode: widget.uiPerformanceMode,
            onSeek: _onSeek,
            onSeekStart: widget.onInteract,
            onSeekEnd: widget.onInteract,
          ),
          const SizedBox(height: 12),

          // ── Controls Row ──
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
                  fontFeatures: [FontFeature.tabularFigures()],
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
              const SizedBox(width: 16),
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
              IconButton(
                icon: Icon(
                  widget.isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: AppPalette.white,
                  size: 28,
                ),
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
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: coreControls,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Custom Seekbar
// ════════════════════════════════════════════════════════════════════════════

class _PremiumSeekbar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final List<Chapter> chapters;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final bool uiPerformanceMode;

  const _PremiumSeekbar({
    required this.position,
    required this.duration,
    required this.chapters,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.uiPerformanceMode,
  });

  @override
  State<_PremiumSeekbar> createState() => _PremiumSeekbarState();
}

class _PremiumSeekbarState extends State<_PremiumSeekbar> {
  bool _isHovering = false;
  bool _isDragging = false;
  double _hoverX = 0.0;
  double _dragX = 0.0;

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  void _updateHover(PointerEvent event, double maxWidth) {
    if (maxWidth <= 0) return;
    setState(() {
      _hoverX = event.localPosition.dx.clamp(0.0, maxWidth);
    });
  }

  void _handleDragUpdate(double localDx, double maxWidth) {
    if (maxWidth <= 0) return;
    setState(() {
      _dragX = localDx.clamp(0.0, maxWidth);
      _hoverX = _dragX; // Keep tooltip aligned with drag
    });

    final percentage = _dragX / maxWidth;
    final seekTo = Duration(
      milliseconds: (widget.duration.inMilliseconds * percentage).toInt(),
    );
    widget.onSeek(seekTo);
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds > 0
        ? widget.duration.inMilliseconds.toDouble()
        : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (e) => setState(() => _isHovering = true),
      onExit: (e) => setState(() => _isHovering = false),
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) _updateHover(e, box.size.width);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;

          // Current playhead percentage
          double currentPercentage = widget.position.inMilliseconds / maxMs;
          if (_isDragging) {
            currentPercentage = _dragX / maxWidth;
          }
          currentPercentage = currentPercentage.clamp(0.0, 1.0);

          // Hover percentage
          final hoverPercentage = (_hoverX / maxWidth).clamp(0.0, 1.0);
          final hoverDuration = Duration(
            milliseconds: (hoverPercentage * maxMs).toInt(),
          );

          // Visual heights
          final bool isExpanded = _isHovering || _isDragging;
          final double trackHeight = isExpanded ? 8.0 : 4.0;
          final double thumbSize = isExpanded ? 16.0 : 0.0;

          // Tooltip Position Constraints
          const tooltipWidth = 60.0;
          double tooltipLeft = _hoverX - (tooltipWidth / 2);
          if (tooltipLeft < 0) tooltipLeft = 0;
          if (tooltipLeft > maxWidth - tooltipWidth) {
            tooltipLeft = maxWidth - tooltipWidth;
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              widget.onSeekStart();
              _handleDragUpdate(d.localPosition.dx, maxWidth);
            },
            onTapUp: (_) => widget.onSeekEnd(),
            onHorizontalDragStart: (d) {
              widget.onSeekStart();
              setState(() {
                _isDragging = true;
                _isHovering = true;
              });
              _handleDragUpdate(d.localPosition.dx, maxWidth);
            },
            onHorizontalDragUpdate: (d) =>
                _handleDragUpdate(d.localPosition.dx, maxWidth),
            onHorizontalDragEnd: (_) {
              setState(() => _isDragging = false);
              widget.onSeekEnd();
            },
            onHorizontalDragCancel: () => setState(() => _isDragging = false),
            child: SizedBox(
              height: 40, // Generous hit area
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  // 1. Inactive Track (Base)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    height: trackHeight,
                    width: maxWidth,
                    decoration: BoxDecoration(
                      color: AppPalette.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  // 2. Hover Track (Grayish fill tracking the mouse)
                  AnimatedContainer(
                    duration: _isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    height: trackHeight,
                    width: _hoverX,
                    decoration: BoxDecoration(
                      // ── FIXED: Fades out to 0 opacity when not hovering ──
                      color: AppPalette.white.withValues(
                        alpha: isExpanded ? 0.35 : 0.0,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  // 3. Active Track (Whiter progress fill)
                  AnimatedContainer(
                    duration: _isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    height: trackHeight,
                    width: maxWidth * currentPercentage,
                    decoration: BoxDecoration(
                      color: AppPalette.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  // 4. Chapter Markers (Black cutouts)
                  for (final chapter in widget.chapters) ...[
                    if (chapter.start.inMilliseconds > 0 &&
                        chapter.start.inMilliseconds < maxMs)
                      Positioned(
                        left: (chapter.start.inMilliseconds / maxMs) * maxWidth,
                        child: Container(
                          width: 2.5,
                          height: trackHeight,
                          color: AppPalette.base.withValues(alpha: 0.95),
                        ),
                      ),
                  ],

                  // 5. Thumb (Scrubber circle)
                  Positioned(
                    left: (maxWidth * currentPercentage) - (thumbSize / 2),
                    child: AnimatedContainer(
                      duration: _isDragging
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      curve: Curves
                          .easeOutCubic, // ── FIXED: Prevents < 0.0 overshoot crash ──
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        color: AppPalette.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppPalette.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 6. Tooltip (Floating timestamp bubble)
                  if (isExpanded)
                    Positioned(
                      top: -10,
                      left: tooltipLeft,
                      child: Container(
                        width: tooltipWidth,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: AppPalette.black.withValues(
                            alpha: widget.uiPerformanceMode ? 0.95 : 0.75,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppPalette.white.withValues(alpha: 0.1),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _formatDuration(hoverDuration),
                          style: const TextStyle(
                            color: AppPalette.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
