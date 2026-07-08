import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_palette.dart';
import '../services/theater_data.dart';

class Seekbar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final List<Chapter> chapters;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final bool uiPerformanceMode;
  final bool dpadModeActive;

  const Seekbar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.chapters,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.uiPerformanceMode,
    this.dpadModeActive = false,
  });

  @override
  State<Seekbar> createState() => _SeekbarState();
}

class _SeekbarState extends State<Seekbar> {
  bool _isHovering = false;
  bool _isDragging = false;
  bool _isFocused = false;
  double _hoverX = 0.0;
  double _dragX = 0.0;

  late final FocusNode _focusNode;
  static const Duration _keyboardSeekStep = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'Seekbar');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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

  // ── Left/Right seek the focused seekbar directly — a keyboard
  // accessibility affordance independent of D-Pad mode (someone who tabs
  // here on a plain desktop keyboard expects arrow keys to scrub, same as a
  // native <input type="range">). Anything else (Up/Down/Tab) is left
  // `ignored` so it bubbles up to whatever FocusTraversalPolicy is in charge
  // and moves focus elsewhere instead of getting stuck here. ──
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    Duration? target;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      target = widget.position - _keyboardSeekStep;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      target = widget.position + _keyboardSeekStep;
    }
    if (target == null) return KeyEventResult.ignored;

    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > widget.duration ? widget.duration : target);
    widget.onSeekStart();
    widget.onSeek(clamped);
    widget.onSeekEnd();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds > 0
        ? widget.duration.inMilliseconds.toDouble()
        : 1.0;

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: _handleKey,
      child: MouseRegion(
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

            double currentPercentage = widget.position.inMilliseconds / maxMs;
            if (_isDragging) currentPercentage = _dragX / maxWidth;
            currentPercentage = currentPercentage.clamp(0.0, 1.0);

            final double bufferPercentage =
                (widget.buffer.inMilliseconds / maxMs).clamp(0.0, 1.0);

            final hoverPercentage = (_hoverX / maxWidth).clamp(0.0, 1.0);
            final hoverDuration = Duration(
              milliseconds: (hoverPercentage * maxMs).toInt(),
            );

            // ── D-Pad focus expands the track exactly like a mouse hover
            // would — a remote-only user still gets the easier-to-hit,
            // easier-to-read expanded state. ──
            final bool showDpadFocus = _isFocused && widget.dpadModeActive;
            final bool isExpanded = _isHovering || _isDragging || showDpadFocus;
            final double trackHeight = isExpanded ? 8.0 : 4.0;
            final double thumbSize = isExpanded ? 16.0 : 0.0;

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
                height: 40,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    // 0. D-Pad focus ring — behind everything else, only ever
                    // visible in D-Pad mode.
                    if (showDpadFocus)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: trackHeight + 12,
                            width: maxWidth,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppPalette.primary.withValues(
                                  alpha: 0.8,
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // 1. Background Track (Faint Outline)
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

                    // ── 2. Buffer Track (Medium Opaque) ──
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: trackHeight,
                      width: maxWidth * bufferPercentage,
                      decoration: BoxDecoration(
                        color: AppPalette.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),

                    // 3. Hover Ghost Track
                    AnimatedContainer(
                      duration: _isDragging
                          ? Duration.zero
                          : const Duration(milliseconds: 100),
                      height: trackHeight,
                      width: _hoverX,
                      decoration: BoxDecoration(
                        color: AppPalette.white.withValues(
                          alpha: isExpanded ? 0.2 : 0.0,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),

                    // 4. Actual Position Track (Solid White)
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

                    // 5. Chapter Markers (Cuts through the tracks)
                    for (final chapter in widget.chapters) ...[
                      if (chapter.start.inMilliseconds > 0 &&
                          chapter.start.inMilliseconds < maxMs)
                        Positioned(
                          left:
                              (chapter.start.inMilliseconds / maxMs) * maxWidth,
                          child: Container(
                            width: 2.5,
                            height: trackHeight,
                            color: AppPalette.base.withValues(alpha: 0.95),
                          ),
                        ),
                    ],

                    // 6. Playhead Thumb
                    Positioned(
                      left: (maxWidth * currentPercentage) - (thumbSize / 2),
                      child: AnimatedContainer(
                        duration: _isDragging
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
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

                    // 7. Hover/Focus Tooltip — falls back to the current
                    // position (not the stale hover position, which would
                    // default to 0:00) when D-Pad-focused without the mouse
                    // ever having moved.
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
                            _formatDuration(
                              showDpadFocus && !_isHovering && !_isDragging
                                  ? widget.position
                                  : hoverDuration,
                            ),
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
      ),
    );
  }
}
