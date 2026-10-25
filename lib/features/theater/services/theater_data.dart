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

  /// Builds a [Chapter] with skippability and label derived from [title], so
  /// every chapter source classifies identically.
  factory Chapter.fromTitle({
    required String title,
    required Duration start,
    required Duration end,
  }) {
    final skippable = _isChapterSkippable(title);
    return Chapter(
      title: title,
      start: start,
      end: end,
      isSkippable: skippable,
      skipLabel: skippable ? _getSkipLabel(title) : null,
    );
  }
}

// Chapter-skippability classification.
bool isOpTitle(String t) => t == 'op' || t == 'ncop' || t.contains('opening');

List<Chapter> fixIntroSkip(List<Chapter> allTags) {
  final tag = allTags.indexWhere((e) => e.title.toLowerCase() == 'intro');
  if (tag == -1) return allTags;

  final all = allTags.map((e) => e.title.toLowerCase());
  if (all.any(isOpTitle)) {
    return allTags
        .map(
          (e) => e.title.toLowerCase() == 'intro'
              ? Chapter(
                  title: e.title,
                  start: e.start,
                  end: e.end,
                  skipLabel: e.skipLabel,
                )
              : e,
        )
        .toList();
  }

  return allTags;
}

bool _isChapterSkippable(String title) {
  final t = title.toLowerCase().trim();

  // Story segments are never skipped.
  if (t == 'avant' || t == 'prologue' || t == 'epilogue') {
    return false;
  }

  // Theme songs; short codes match exactly to avoid "Operation"/"Wedding".
  if (t == 'op' || t.contains('opening') || t == 'ncop' || t == 'intro') {
    return true;
  }

  // Next-episode previews.
  if (t == 'pv' || t.contains('preview') || t.contains('next episode')) {
    return true;
  }

  return false;
}

String _getSkipLabel(String title) {
  final t = title.toLowerCase().trim();

  if (t == 'op' ||
      t.contains('opening') ||
      t.contains('intro') ||
      t == 'ncop') {
    return 'Skip Opening';
  }
  if (t == 'ed' ||
      t.contains('ending') ||
      t.contains('credits') ||
      t == 'nced') {
    return 'Skip Ending';
  }
  if (t == 'pv' || t.contains('preview') || t.contains('next episode')) {
    return 'Skip Preview';
  }

  return 'Skip';
}

/// A raw (title, start) marker from mpv or Media3; ends are derived by
/// [buildChaptersFromRaw].
class RawChapterMarker {
  final String title;
  final Duration start;

  const RawChapterMarker({required this.title, required this.start});
}

/// Turns (title, start) markers into classified [Chapter]s, inferring each end
/// from the next start (or [totalDuration]). Sorts [raw] first, since Media3's
/// `Format.metadata` doesn't arrive in chronological order.
List<Chapter> buildChaptersFromRaw(
  List<RawChapterMarker> raw,
  Duration totalDuration,
) {
  final sorted = [...raw]..sort((a, b) => a.start.compareTo(b.start));

  final chapters = <Chapter>[];
  for (var i = 0; i < sorted.length; i++) {
    final end = i < sorted.length - 1 ? sorted[i + 1].start : totalDuration;
    chapters.add(
      Chapter.fromTitle(
        title: sorted[i].title,
        start: sorted[i].start,
        end: end,
      ),
    );
  }

  return fixIntroSkip(chapters);
}
