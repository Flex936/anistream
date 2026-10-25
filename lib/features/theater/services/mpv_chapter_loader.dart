import 'package:media_kit/media_kit.dart';

import 'theater_data.dart';

/// Reads chapter markers from mpv's `chapter-list` property; ends and
/// skippability come from [buildChaptersFromRaw].
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
