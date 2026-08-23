import 'package:media_kit/media_kit.dart';

import 'theater_data.dart';

/// Reads chapter markers off mpv's own `chapter-list` property —
/// media_kit exposes this directly once media_kit/libmpv has demuxed
/// enough of the container to know it, so this needs no extraction step
/// of its own, unlike the Media3-native path (see
/// native_chapter_parser.dart), which has to ask Media3 to parse the
/// container itself. Only [Chapter.title]/[Chapter.start] are read
/// natively; end times and skippability classification are derived by
/// [buildChaptersFromRaw], the same shared logic the Media3 path uses.
Future<List<Chapter>> loadChapters(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return [];

  try {
    final countStr = await platform.getProperty('chapter-list/count');
    final count = int.tryParse(countStr) ?? 0;
    if (count == 0) return [];

    final raw = <RawChapterMarker>[];
    for (var i = 0; i < count; i++) {
      final title = await platform.getProperty('chapter-list/$i/title');
      final timeStr = await platform.getProperty('chapter-list/$i/time');
      final seconds = double.tryParse(timeStr) ?? 0.0;
      raw.add(
        RawChapterMarker(
          title: title,
          start: Duration(milliseconds: (seconds * 1000).round()),
        ),
      );
    }

    return buildChaptersFromRaw(raw, player.state.duration);
  } catch (_) {
    return [];
  }
}