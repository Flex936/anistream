import 'package:flutter/material.dart';

import '../services/native_subtitle_parser.dart';

/// Renders [StyledCue]s from [NativeSubtitleParser] — real positioning
/// and per-run styling from Media3's own TtmlParser/SsaParser, not the
/// single-fixed-style plain text video_player's `ClosedCaption` widget
/// is limited to. Sits in the same spot `ClosedCaption` used to (see
/// ExoTheaterScreen), driven the same way: rebuilt on every position
/// tick via a `ValueListenableBuilder`.
class StyledSubtitleView extends StatelessWidget {
  final List<StyledCue> cues;
  final Duration position;

  const StyledSubtitleView({
    super.key,
    required this.cues,
    required this.position,
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

  /// Cue.line/Cue.position are 0.0-1.0 fractions of the video area,
  /// exactly as ExoPlayer's own SubtitleView interprets Media3's Cue —
  /// see LINE_TYPE_FRACTION in the Android docs. A cue that doesn't
  /// specify either (both null, from Cue.DIMEN_UNSET on the native
  /// side) falls back to the conventional bottom-center every player
  /// defaults to when a cue carries no position of its own.
  ///
  /// Simplification (v1): position/line are treated as the cue box's
  /// horizontal center and top edge respectively, ignoring
  /// Cue.positionAnchor/lineAnchor's START/MIDDLE/END distinction —
  /// this covers the large majority of real fansub \pos-style
  /// overrides. SubtitleParserPlugin.kt already sends both anchor
  /// values across the bridge, unused here, for exactly this follow-up
  /// if a release that leans on them shows up visibly off.
  Widget _positionCue(StyledCue cue, double width, double height) {
    final hasPosition = cue.line != null || cue.position != null;

    if (!hasPosition) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 24,
        child: Align(
          alignment: _horizontalAlignmentFor(cue.textAlignment),
          child: _CueText(cue: cue),
        ),
      );
    }

    return Positioned(
      top: (cue.line ?? 0.85).clamp(0.0, 1.0) * height,
      left: 0,
      width: width,
      child: Align(
        alignment: Alignment((cue.position ?? 0.5).clamp(0.0, 1.0) * 2 - 1, 0),
        child: _CueText(cue: cue),
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
  const _CueText({required this.cue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: const Color(0x99000000),
      child: Text.rich(
        TextSpan(
          children: [
            for (final run in cue.runs)
              TextSpan(text: run.text, style: _styleFor(run)),
          ],
        ),
        textAlign: _textAlignFor(cue.textAlignment),
      ),
    );
  }

  TextStyle _styleFor(StyledTextRun run) {
    final decorations = <TextDecoration>[
      if (run.underline) TextDecoration.underline,
      if (run.strikethrough) TextDecoration.lineThrough,
    ];
    return TextStyle(
      color: run.foregroundColor ?? Colors.white,
      backgroundColor: run.backgroundColor,
      fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      fontSize: 18,
    );
  }

  TextAlign _textAlignFor(CueTextAlignment? alignment) => switch (alignment) {
    CueTextAlignment.start => TextAlign.left,
    CueTextAlignment.end => TextAlign.right,
    _ => TextAlign.center,
  };
}
