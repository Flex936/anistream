import 'package:flutter/services.dart';

/// One contiguous, identically-styled run of text within a [StyledCue].
/// Mirrors SubtitleParserPlugin.kt's `extractRuns()` output — Media3's
/// TtmlParser/SsaParser attach real Android style spans (StyleSpan,
/// UnderlineSpan, StrikethroughSpan, *ColorSpan) to a cue's text, and
/// this is that same information, flattened into a form Dart's
/// [TextSpan] can build from directly.
class StyledTextRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final Color? foregroundColor;
  final Color? backgroundColor;

  const StyledTextRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.foregroundColor,
    this.backgroundColor,
  });

  factory StyledTextRun.fromMap(Map<Object?, Object?> map) {
    return StyledTextRun(
      text: map['text'] as String? ?? '',
      bold: map['bold'] as bool? ?? false,
      italic: map['italic'] as bool? ?? false,
      underline: map['underline'] as bool? ?? false,
      strikethrough: map['strikethrough'] as bool? ?? false,
      foregroundColor: _colorFromArgb(map['foregroundColor'] as int?),
      backgroundColor: _colorFromArgb(map['backgroundColor'] as int?),
    );
  }

  static Color? _colorFromArgb(int? argb) => argb == null ? null : Color(argb);
}

/// Mirrors Media3's `Layout.Alignment` as sent by SubtitleParserPlugin's
/// `alignmentName()`.
enum CueTextAlignment { start, center, end }

/// Mirrors Media3's `@Cue.TextSizeType` as sent by SubtitleParserPlugin's
/// `textSizeTypeName()`. Only the two variants SsaParser can actually
/// produce for us are represented here — see [StyledCue.fontSizeFraction]
/// for why `absolute` is deliberately never treated as a usable size.
enum CueTextSizeType { fractional, absolute }

/// One subtitle cue with real timing, positioning, and per-run styling —
/// what [NativeSubtitleParser] hands back from Media3's own TtmlParser/
/// SsaParser. Deliberately NOT a video_player `Caption` — those only
/// ever carry plain text, which is exactly the limitation this whole
/// native-parser path exists to get past.
class StyledCue {
  final Duration start;
  final Duration end;
  final List<StyledTextRun> runs;

  /// 0.0-1.0 fraction of the video's height, or null for "use the
  /// default bottom position" — mirrors `Cue.line`/`Cue.DIMEN_UNSET`.
  final double? line;

  /// 0.0-1.0 fraction of the video's width, or null for "use the
  /// default horizontal centering" — mirrors `Cue.position`.
  final double? position;

  final CueTextAlignment? textAlignment;

  /// Raw value from `Cue.textSize`, or null when Media3 resolved no
  /// explicit size for this cue (`Cue.DIMEN_UNSET`). Meaningless without
  /// [textSizeType] — read [fontSizeFraction] instead of this directly.
  final double? textSize;

  /// How [textSize] should be interpreted, or null alongside a null
  /// [textSize]. See [fontSizeFraction].
  final CueTextSizeType? textSizeType;

  const StyledCue({
    required this.start,
    required this.end,
    required this.runs,
    this.line,
    this.position,
    this.textAlignment,
    this.textSize,
    this.textSizeType,
  });

  factory StyledCue.fromMap(Map<Object?, Object?> map) {
    return StyledCue(
      start: Duration(milliseconds: (map['startMs'] as num).toInt()),
      end: Duration(milliseconds: (map['endMs'] as num).toInt()),
      runs: ((map['runs'] as List<Object?>?) ?? const [])
          .map((r) => StyledTextRun.fromMap(r as Map<Object?, Object?>))
          .toList(),
      line: (map['line'] as num?)?.toDouble(),
      position: (map['position'] as num?)?.toDouble(),
      textAlignment: _alignmentFromName(map['textAlignment'] as String?),
      textSize: (map['textSize'] as num?)?.toDouble(),
      textSizeType: _textSizeTypeFromName(map['textSizeType'] as String?),
    );
  }

  /// [textSize] as a 0.0-1.0 fraction of the video's height, or null if
  /// there's nothing here worth trusting.
  ///
  /// Only [CueTextSizeType.fractional] is ever returned — ASS's own
  /// Fontsize field is defined relative to the script's PlayResY, a
  /// virtual reference resolution SsaParser has no way to reconcile
  /// against a real device pixel value at parse time (parsing runs
  /// against raw subtitle bytes alone, with no knowledge of the eventual
  /// video/view size) — so a resolved `absolute` size has no reliable
  /// meaning to multiply against anything on this side of the bridge.
  /// Callers are better off falling back to their own default than
  /// rendering a guess.
  double? get fontSizeFraction =>
      textSizeType == CueTextSizeType.fractional ? textSize : null;

  static CueTextAlignment? _alignmentFromName(String? name) => switch (name) {
    'start' => CueTextAlignment.start,
    'center' => CueTextAlignment.center,
    'end' => CueTextAlignment.end,
    _ => null,
  };

  static CueTextSizeType? _textSizeTypeFromName(String? name) => switch (name) {
    'fractional' => CueTextSizeType.fractional,
    'absolute' => CueTextSizeType.absolute,
    _ => null,
  };
}

/// Format accepted by the native parser — and, one-to-one, by the Go
/// server's `?format=` query param (see remote_streaming_controller.dart
/// / anistream_server's subtitle_extractor.go). Swapping the whole
/// pipeline from ASS to TTML is exactly: change every use of
/// [NativeSubtitleFormat.ass] in exo_theater_screen.dart to
/// [NativeSubtitleFormat.ttml]. Nothing else in the Dart or Kotlin code
/// branches on format beyond that one enum value.
enum NativeSubtitleFormat {
  ass('ass'),
  ttml('ttml');

  final String wireValue;
  const NativeSubtitleFormat(this.wireValue);

  @override
  String toString() => wireValue;
}

/// Thin MethodChannel client for `SubtitleParserPlugin`
/// (android/app/src/main/kotlin/.../SubtitleParserPlugin.kt) — hands raw
/// subtitle bytes to Media3's own TtmlParser/SsaParser and gets back
/// real cue timing, positioning, and style-span data, instead of
/// video_player's plain-text-only ClosedCaptionFile mechanism.
///
/// Android only today — SubtitleParserPlugin wraps androidx.media3
/// classes with no iOS/macOS equivalent wired up. Calling this on
/// another platform throws a [MissingPluginException]; callers on the
/// experimental-player path should only reach this after confirming
/// they're on a platform SubtitleParserPlugin is registered on.
abstract final class NativeSubtitleParser {
  static const _channel = MethodChannel('anistream/subtitle_parser');

  static Future<List<StyledCue>> parse(
    Uint8List bytes,
    NativeSubtitleFormat format,
  ) async {
    final result = await _channel.invokeMethod<List<Object?>>('parseSubtitle', {
      'bytes': bytes,
      'format': format.wireValue,
    });
    return (result ?? const [])
        .map((c) => StyledCue.fromMap(c as Map<Object?, Object?>))
        .toList();
  }
}