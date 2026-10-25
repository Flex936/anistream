import 'package:flutter/services.dart';

/// An identically styled run of text in a [StyledCue], flattened from Media3's
/// style spans (SubtitleParserPlugin's `extractRuns()`) for [TextSpan].
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

/// Mirrors Media3's `Layout.Alignment` (see SubtitleParserPlugin).
enum CueTextAlignment { start, center, end }

/// Mirrors Media3's `@Cue.TextSizeType`; only the variants SsaParser produces.
enum CueTextSizeType { fractional, absolute }

/// One cue with timing, position, and per-run styling from
/// [NativeSubtitleParser]. See ARCHITECTURE.md § 10.
class StyledCue {
  final Duration start;
  final Duration end;
  final List<StyledTextRun> runs;

  /// Fraction (0-1) of video height; null means the default bottom position.
  final double? line;

  /// Fraction (0-1) of video width; null means the default centering.
  final double? position;

  final CueTextAlignment? textAlignment;

  /// Raw `Cue.textSize`, or null if unset; read [fontSizeFraction] instead.
  final double? textSize;

  /// How [textSize] is interpreted; null when [textSize] is null.
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

  /// [textSize] as a 0-1 fraction of video height; null unless fractional.
  /// See ARCHITECTURE.md § 10.
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

/// Wire format shared by the native parser and the server's `?format=` param.
/// See ARCHITECTURE.md § 10.
enum NativeSubtitleFormat {
  ass('ass'),
  ttml('ttml');

  final String wireValue;
  const NativeSubtitleFormat(this.wireValue);

  @override
  String toString() => wireValue;
}

/// MethodChannel client for `SubtitleParserPlugin`: parses raw subtitle bytes
/// with Media3's TtmlParser/SsaParser. Android only; other platforms throw
/// [MissingPluginException]. See ARCHITECTURE.md § 4.
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
