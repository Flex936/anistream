import 'package:flutter/services.dart';

/// A raw chapter marker from Media3's `Chapter` metadata. [title] may be null;
/// [hidden] mirrors `Chapter.isHidden()` and is left for callers to filter.
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

/// MethodChannel client for `ChapterMetadataPlugin`: probes [url] with a
/// throwaway ExoPlayer and returns raw markers. Android only; other platforms
/// throw [MissingPluginException]. See ARCHITECTURE.md § 4.
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
