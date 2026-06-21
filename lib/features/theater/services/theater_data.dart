import 'package:media_kit/media_kit.dart';

class Chapter {
  final String title;
  final Duration start;
  const Chapter({required this.title, required this.start});
}

Future<List<Chapter>> loadChapters(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return [];

  try {
    final countStr = await platform.getProperty('chapter-list/count');
    final count = int.tryParse(countStr) ?? 0;
    if (count == 0) return [];

    final chapters = <Chapter>[];
    for (var i = 0; i < count; i++) {
      final title = await platform.getProperty('chapter-list/$i/title');
      final timeStr = await platform.getProperty('chapter-list/$i/time');
      final seconds = double.tryParse(timeStr) ?? 0.0;
      chapters.add(
        Chapter(
          title: title.isEmpty ? 'Chapter ${i + 1}' : title,
          start: Duration(milliseconds: (seconds * 1000).round()),
        ),
      );
    }
    return chapters;
  } catch (_) {
    return []; // file has no chapter metadata — totally normal
  }
}
