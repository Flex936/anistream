import 'package:flutter/material.dart';

import '../services/native_subtitle_parser.dart';

/// Fallback text size, as a fraction of the video's height, for a cue
/// with no usable size info from Media3 — see [StyledCue.fontSizeFraction].
/// Kept as a fraction rather than the flat px value this replaces, so
/// subtitles stay roughly the same relative size across a phone window,
/// a maximized desktop window, and a TV, instead of looking right only
/// on whichever one the flat value happened to be tuned against. 0.045
/// reproduces close to the old 18px constant at a typical phone-landscape
/// video height (~400dp), while scaling up sensibly on a much taller TV
/// display.
const double _kDefaultFontSizeFraction = 0.045;

/// Clamp bounds (logical px) for the resolved cue font size, regardless
/// of whether it came from Media3 or [_kDefaultFontSizeFraction] — guards
/// against an unusual release's Fontsize, or an unusual video aspect
/// ratio, producing text that's unreadably small or large enough to
/// meaningfully exceed the fixed cue-box height _positionCue's own
/// estimatedCueBoxHeight assumes (see that constant's doc comment below).
const double _kMinFontSize = 12.0;
const double _kMaxFontSize = 48.0;

/// Renders [StyledCue]s from [NativeSubtitleParser] — real positioning
/// and per-run styling from Media3's own TtmlParser/SsaParser, not the
/// single-fixed-style plain text video_player's `ClosedCaption` widget
/// is limited to. Sits in the same spot `ClosedCaption` used to (see
/// ExoTheaterScreen), driven the same way: rebuilt on every position
/// tick via a `ValueListenableBuilder`.
///
/// Must be given the video's true, full-height bounds (not pre-shrunk to
/// dodge the controls bar) — `Cue.line`/`Cue.position` are fractions of
/// the *real* video area, the same denominator ExoPlayer's own
/// SubtitleView would use, so measuring against anything smaller shifts
/// every cue upward from where the source file actually places it.
/// [reservedBottom] is how this widget still avoids the controls: rather
/// than shrinking its own bounds, it clamps individual cues away from
/// that zone at layout time — see [_positionCue].
///
/// Font size is resolved per cue too, not just position — see
/// [StyledCue.fontSizeFraction] and [_CueText]'s use of it. Still not
/// per-run: an inline mid-line `\fs` override inside a single ASS cue
/// isn't distinguished from the rest of that cue's text, only cue-level
/// sizing (a Signs style rendering larger than Dialogue, the common
/// case) is.
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
  ///
  /// Both branches keep cues clear of [reservedBottom] (the controls
  /// bar) explicitly, now that this widget is measured against the
  /// video's true full height rather than a pre-shrunk area — nothing
  /// upstream reserves that space on this widget's behalf anymore.
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

    // Generous estimate for a cue box's own rendered height — enough
    // headroom for several wrapped/explicit-newline lines at _CueText's
    // resolved font size. Not a real per-cue measurement (that would mean
    // laying the text out twice, once to measure and once to render, for
    // every active cue on every frame) — just enough to keep a
    // positioned sign's box from dipping into the reserved zone at all,
    // which is the actual bug being fixed here, not pixel-perfect
    // placement for unusually tall cues. A cue rendered at
    // _kMaxFontSize and wrapped across several lines can still exceed
    // this in principle — same known limitation as before automatic
    // sizing, just worth re-flagging now that font size isn't fixed.
    const estimatedCueBoxHeight = 100.0;
    final maxAllowedTop =
        (height - reservedBottom - estimatedCueBoxHeight).clamp(0.0, height);
    final rawTop = (cue.line ?? 0.85).clamp(0.0, 1.0) * height;

    return Positioned(
      top: rawTop.clamp(0.0, maxAllowedTop),
      left: 0,
      width: width,
      child: Align(
        alignment: Alignment(
          (cue.position ?? 0.5).clamp(0.0, 1.0) * 2 - 1,
          0,
        ),
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

  /// The real video area's height, in the same logical-px space
  /// [StyledSubtitleView]'s `LayoutBuilder` measures against — needed
  /// here because [StyledCue.fontSizeFraction] is itself a fraction of
  /// that same height, matching every other piece of Cue geometry this
  /// pipeline already treats as video-relative rather than
  /// screen-relative.
  final double videoHeight;

  const _CueText({required this.cue, required this.videoHeight});

  /// Resolved once per cue, not per run — Media3 only gives us font
  /// size at the cue level (see class doc) — and clamped so neither a
  /// missing style nor an unusually large/small one in some release
  /// produces unreadable or absurdly oversized text.
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

  // Deliberately no background box (see class doc for why — this style's
  // own BorderStyle:1 means "outline + shadow", not "opaque box"; that
  // field just isn't something Media3 exposes to us per-run). A few
  // small, near-zero-blur shadows stacked around each glyph fake a
  // solid-looking outline instead — the standard way to get ASS-style
  // readability in Flutter, since Text has no native stroke support
  // outside a custom Paint. Always black: the real per-line outline
  // color (\3c) isn't available to us any more than \c is, so this is a
  // reasonable universal stand-in, not a faithful reproduction of
  // whatever color a given line's outline actually specifies.
  static const List<Shadow> _outline = [
    Shadow(offset: Offset(-1, -1), color: Colors.black),
    Shadow(offset: Offset(1, -1), color: Colors.black),
    Shadow(offset: Offset(-1, 1), color: Colors.black),
    Shadow(offset: Offset(1, 1), color: Colors.black),
    Shadow(offset: Offset(0, 0), color: Colors.black, blurRadius: 3),
  ];

  TextStyle _styleFor(StyledTextRun run, double fontSize) {
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
      fontSize: fontSize,
      shadows: _outline,
    );
  }

  TextAlign _textAlignFor(CueTextAlignment? alignment) => switch (alignment) {
    CueTextAlignment.start => TextAlign.left,
    CueTextAlignment.end => TextAlign.right,
    _ => TextAlign.center,
  };
}