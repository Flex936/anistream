import 'package:flutter/services.dart';

/// One raw chapter marker as reported by Media3's own Chapter metadata
/// support (`androidx.media3.extractor.metadata.Chapter`, shipped in
/// media3-extractor 1.11.0) via [NativeChapterParser]. [title] is
/// nullable — `Chapter.getTitle()` itself can return null — and [hidden]
/// mirrors `Chapter.isHidden()`: "should not be shown in a table of
/// contents UI." This layer doesn't filter on [hidden] itself; callers
/// decide whether to drop hidden markers before building real [Chapter]s
/// from them.
class NativeChapterMarker {
  final String? title;
  final int startMs;
  final bool hidden;

  const NativeChapterMarker({
    this.title,
    required this.startMs,
    this.hidden = false,
  });

  factory NativeChapterMarker.fromMap(Map<Object?, Object?> map) =>
      NativeChapterMarker(
        title: map['title'] as String?,
        startMs: (map['startMs'] as num).toInt(),
        hidden: map['hidden'] as bool? ?? false,
      );
}

/// Thin MethodChannel client for `ChapterMetadataPlugin`
/// (android/app/src/main/kotlin/.../ChapterMetadataPlugin.kt) — opens
/// [url] through a throwaway ExoPlayer purely to read whatever Chapter
/// metadata entries Media3's own extractors attach to the container's
/// tracks, then hands back the raw (title, start) markers. Callers turn
/// these into real [Chapter]s via `buildChaptersFromRaw`
/// (theater_data.dart) — this layer only talks to the platform channel,
/// it doesn't classify or derive end times itself.
///
/// Android only today — ChapterMetadataPlugin wraps androidx.media3
/// classes with no iOS/macOS equivalent wired up, same constraint as
/// [NativeSubtitleParser]. Calling this on another platform throws a
/// [MissingPluginException].
abstract final class NativeChapterParser {
  static const _channel = MethodChannel('anistream/chapter_parser');

  static Future<List<NativeChapterMarker>> extractChapters(String url) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      'extractChapters',
      {'url': url},
    );
    return (result ?? const [])
        .map((c) => NativeChapterMarker.fromMap(c as Map<Object?, Object?>))
        .toList();
  }
}