import 'package:media_kit/media_kit.dart';

class Chapter {
  final String title;
  final Duration start;
  final Duration end;
  final bool isSkippable;

  const Chapter({
    required this.title,
    required this.start,
    required this.end,
    this.isSkippable = false,
  });

  String get skipLabel {
    final t = title.toLowerCase();
    if (t.contains('op') || t.contains('intro')) return 'Skip Intro';
    if (t.contains('ed') || t.contains('ending')) return 'Skip Ending';
    if (t.contains('recap')) return 'Skip Recap';
    return 'Skip';
  }
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

      final titleLower = title.toLowerCase();
      final isSkippable =
          titleLower.contains('op') ||
          titleLower.contains('ed') ||
          titleLower.contains('intro') ||
          titleLower.contains('ending');

      chapters.add(
        Chapter(
          title: title,
          start: Duration(milliseconds: (seconds * 1000).round()),
          end: Duration.zero,
          isSkippable: isSkippable,
        ),
      );
    }

    // Calculate end times
    for (int i = 0; i < chapters.length; i++) {
      final end = (i < chapters.length - 1)
          ? chapters[i + 1].start
          : player.state.duration;

      chapters[i] = Chapter(
        title: chapters[i].title,
        start: chapters[i].start,
        end: end,
        isSkippable: chapters[i].isSkippable,
      );
    }

    return chapters;
  } catch (_) {
    return [];
  }
}
