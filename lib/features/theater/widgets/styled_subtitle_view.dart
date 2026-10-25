import 'package:flutter/material.dart';

import '../services/native_subtitle_parser.dart';

/// Fallback cue font size as a fraction of the video's height.
const double _kDefaultFontSizeFraction = 0.045;

/// Clamp bounds (logical px) for the resolved cue font size.
const double _kMinFontSize = 12.0;
const double _kMaxFontSize = 48.0;

/// Renders [StyledCue]s from [NativeSubtitleParser]. Must be measured against
/// the video's full bounds; cues clear the controls via [reservedBottom].
/// See ARCHITECTURE.md § 10.
class StyledSubtitleView extends StatelessWidget {
  final List<StyledCue> cues;
  final Duration position;
  final double reservedBottom;

  const StyledSubtitleView({
    super.key,
    required this.cues,
    required this.position,
    this.reservedBottom = 0,
  });

  @override
  Widget build(BuildContext context) {
    final active = cues
        .where((c) => position >= c.start && position < c.end)
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            for (final cue in active)
              _positionCue(cue, constraints.maxWidth, constraints.maxHeight),
          ],
        ),
      ),
    );
  }

  /// Bottom-centers [cue] when it has no position, else places it at its
  /// `line`/`position` fractions; either way it clears [reservedBottom].
  Widget _positionCue(StyledCue cue, double width, double height) {
    final hasPosition = cue.line != null || cue.position != null;

    if (!hasPosition) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 24 + reservedBottom,
        child: Align(
          alignment: _horizontalAlignmentFor(cue.textAlignment),
          child: _CueText(cue: cue, videoHeight: height),
        ),
      );
    }

    // Rough box height, not measured (that would lay out every cue twice per
    // build); a very tall wrapped cue can exceed it.
    const estimatedCueBoxHeight = 100.0;
    final maxAllowedTop = (height - reservedBottom - estimatedCueBoxHeight)
        .clamp(0.0, height);
    final rawTop = (cue.line ?? 0.85).clamp(0.0, 1.0) * height;

    return Positioned(
      top: rawTop.clamp(0.0, maxAllowedTop),
      left: 0,
      width: width,
      child: Align(
        alignment: Alignment((cue.position ?? 0.5).clamp(0.0, 1.0) * 2 - 1, 0),
        child: _CueText(cue: cue, videoHeight: height),
      ),
    );
  }

  Alignment _horizontalAlignmentFor(CueTextAlignment? alignment) =>
      switch (alignment) {
        CueTextAlignment.start => Alignment.centerLeft,
        CueTextAlignment.end => Alignment.centerRight,
        _ => Alignment.center,
      };
}

class _CueText extends StatelessWidget {
  final StyledCue cue;

  /// The video area's height; [StyledCue.fontSizeFraction] is relative to it.
  final double videoHeight;

  const _CueText({required this.cue, required this.videoHeight});

  /// Cue-level (not per-run) font size, clamped to [_kMinFontSize]–
  /// [_kMaxFontSize].
  double get _resolvedFontSize {
    final fraction = cue.fontSizeFraction ?? _kDefaultFontSizeFraction;
    return (fraction * videoHeight).clamp(_kMinFontSize, _kMaxFontSize);
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = _resolvedFontSize;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            for (final run in cue.runs)
              TextSpan(text: run.text, style: _styleFor(run, fontSize)),
          ],
        ),
        textAlign: _textAlignFor(cue.textAlignment),
      ),
    );
  }

  // Stacked near-zero-blur shadows fake an outline, since Text has no stroke.
  static const List<Shadow> _blackOutline = [
    Shadow(offset: Offset(-1, -1)),
    Shadow(offset: Offset(1, -1)),
    Shadow(offset: Offset(-1, 1)),
    Shadow(offset: Offset(1, 1)),
    Shadow(blurRadius: 3),
  ];

  static const List<Shadow> _whiteOutline = [
    Shadow(offset: Offset(-1, -1), color: Colors.white),
    Shadow(offset: Offset(1, -1), color: Colors.white),
    Shadow(offset: Offset(-1, 1), color: Colors.white),
    Shadow(offset: Offset(1, 1), color: Colors.white),
    Shadow(color: Colors.white, blurRadius: 3),
  ];

  /// Relative luminance (WCAG) below which a run gets a white outline.
  static const double _darkTextLuminanceThreshold = 0.4;

  /// [_whiteOutline] for a dark [textColor], else [_blackOutline].
  List<Shadow> _outlineFor(Color textColor) =>
      textColor.computeLuminance() < _darkTextLuminanceThreshold
      ? _whiteOutline
      : _blackOutline;

  TextStyle _styleFor(StyledTextRun run, double fontSize) {
    final decorations = <TextDecoration>[
      if (run.underline) TextDecoration.underline,
      if (run.strikethrough) TextDecoration.lineThrough,
    ];
    final color = run.foregroundColor ?? Colors.white;
    return TextStyle(
      color: color,
      backgroundColor: run.backgroundColor,
      fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      fontSize: fontSize,
      shadows: _outlineFor(color),
    );
  }

  TextAlign _textAlignFor(CueTextAlignment? alignment) => switch (alignment) {
    CueTextAlignment.start => TextAlign.left,
    CueTextAlignment.end => TextAlign.right,
    _ => TextAlign.center,
  };
}
