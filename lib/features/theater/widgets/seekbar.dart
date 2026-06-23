import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../services/theater_data.dart';

class Seekbar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final List<Chapter> chapters;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final bool uiPerformanceMode;

  const Seekbar({
    super.key,
    required this.position,
    required this.duration,
    required this.chapters,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.uiPerformanceMode,
  });

  @override
  State<Seekbar> createState() => _SeekbarState();
}

class _SeekbarState extends State<Seekbar> {
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

          double currentPercentage = widget.position.inMilliseconds / maxMs;
          if (_isDragging) currentPercentage = _dragX / maxWidth;
          currentPercentage = currentPercentage.clamp(0.0, 1.0);

          final hoverPercentage = (_hoverX / maxWidth).clamp(0.0, 1.0);
          final hoverDuration = Duration(
            milliseconds: (hoverPercentage * maxMs).toInt(),
          );

          final bool isExpanded = _isHovering || _isDragging;
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
                  AnimatedContainer(
                    duration: _isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    height: trackHeight,
                    width: _hoverX,
                    decoration: BoxDecoration(
                      color: AppPalette.white.withValues(
                        alpha: isExpanded ? 0.35 : 0.0,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
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
