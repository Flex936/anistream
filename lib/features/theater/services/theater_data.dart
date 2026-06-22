import 'package:media_kit/media_kit.dart';

class Chapter {
  final String title;
  final Duration start;
  final Duration end;
  final bool isSkippable;
  final String? skipLabel;

  const Chapter({
    required this.title,
    required this.start,
    required this.end,
    this.isSkippable = false,
    this.skipLabel,
  });
}

// ── Strict Chapter Parsing Logic ──

bool _isChapterSkippable(String title) {
  final t = title.toLowerCase().trim();

  // 1. DO NOT skip story segments (Release groups often name the Prologue "Intro")
  if (t == 'intro' || t == 'avant' || t == 'prologue' || t == 'epilogue') {
    return false;
  }

  // 2. DO skip theme songs (Use strict equality for short codes to prevent false positives like "Operation" or "Wedding")
  if (t == 'op' || t.contains('opening') || t == 'ncop') return true;
  if (t == 'ed' || t.contains('ending') || t == 'nced') return true;

  // 3. DO skip next-episode previews
  if (t == 'pv' || t.contains('preview') || t.contains('next episode')) {
    return true;
  }

  return false;
}

String _getSkipLabel(String title) {
  final t = title.toLowerCase().trim();

  if (t == 'op' || t.contains('opening') || t == 'ncop') return 'Skip Opening';
  if (t == 'ed' || t.contains('ending') || t == 'nced') return 'Skip Ending';
  if (t == 'pv' || t.contains('preview') || t.contains('next episode')) {
    return 'Skip Preview';
  }

  return 'Skip';
}

// ── MKV Metadata Extraction ──

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

      final isSkippable = _isChapterSkippable(title);
      final skipLabel = isSkippable ? _getSkipLabel(title) : null;

      chapters.add(
        Chapter(
          title: title,
          start: Duration(milliseconds: (seconds * 1000).round()),
          end: Duration.zero, // We will calculate this in the next pass
          isSkippable: isSkippable,
          skipLabel: skipLabel,
        ),
      );
    }

    // Calculate end times by looking at the start time of the next chapter
    for (int i = 0; i < chapters.length; i++) {
      final end = (i < chapters.length - 1)
          ? chapters[i + 1].start
          : player.state.duration;

      chapters[i] = Chapter(
        title: chapters[i].title,
        start: chapters[i].start,
        end: end,
        isSkippable: chapters[i].isSkippable,
        skipLabel: chapters[i].skipLabel,
      );
    }

    return chapters;
  } catch (_) {
    return [];
  }
}
