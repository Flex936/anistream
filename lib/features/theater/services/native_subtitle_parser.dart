import 'dart:typed_data';
import 'dart:ui' show Color;

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

  const StyledCue({
    required this.start,
    required this.end,
    required this.runs,
    this.line,
    this.position,
    this.textAlignment,
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
    );
  }

  static CueTextAlignment? _alignmentFromName(String? name) => switch (name) {
    'start' => CueTextAlignment.start,
    'center' => CueTextAlignment.center,
    'end' => CueTextAlignment.end,
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
