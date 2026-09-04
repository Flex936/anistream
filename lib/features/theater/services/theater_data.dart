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

  /// Builds a [Chapter] with [isSkippable]/[skipLabel] derived from
  /// [title] via the shared classification heuristic below — the single
  /// place every chapter source (mpv's native chapter-list property,
  /// Media3's Chapter metadata entries) goes through, so the same title
  /// is classified identically regardless of which engine found it.
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

bool _isChapterSkippable(String title) {
  final t = title.toLowerCase().trim();

  // 1. Do not skip story segments (release groups often name the Prologue "Intro")
  if (t == 'avant' || t == 'prologue' || t == 'epilogue') {
    return false;
  }

  // 2. Do skip theme songs (strict equality for short codes to prevent false positives like "Operation" or "Wedding")
  if (t == 'op' || t.contains('opening') || t.contains('intro') || t == 'ncop')
    return true;
  if (t == 'ed' || t.contains('ending') || t.contains('credits') || t == 'nced')
    return true;

  // 3. Do skip next-episode previews
  if (t == 'pv' || t.contains('preview') || t.contains('next episode')) {
    return true;
  }

  return false;
}

String _getSkipLabel(String title) {
  final t = title.toLowerCase().trim();

  if (t == 'op' || t.contains('opening') || t.contains('intro') || t == 'ncop')
    return 'Skip Opening';
  if (t == 'ed' || t.contains('ending') || t.contains('credits') || t == 'nced')
    return 'Skip Ending';
  if (t == 'pv' || t.contains('preview') || t.contains('next episode')) {
    return 'Skip Preview';
  }

  return 'Skip';
}

/// One raw (title, start) marker as reported by whichever engine found
/// it — mpv's own `chapter-list` property, or Media3's Chapter metadata
/// entries. Deliberately carries no end time — see
/// [buildChaptersFromRaw]'s doc comment for why that's derived centrally
/// instead of by each source individually.
class RawChapterMarker {
  final String title;
  final Duration start;

  const RawChapterMarker({required this.title, required this.start});
}

/// Turns a set of (title, start) markers into fully-classified [Chapter]s
/// with real end times, regardless of which engine supplied [raw].
///
/// Neither mpv's chapter-list property nor Media3's Chapter metadata
/// entries reliably report an end time — most real-world releases only
/// set a chapter's start, leaving players to infer the end from whichever
/// chapter comes next (or the video's own duration, for the last one).
///
/// [raw] is explicitly NOT assumed to already be sorted by start time —
/// confirmed against a real Media3 probe that `Format.metadata` does not
/// come back in chronological order — so this always sorts first. Both
/// chapter sources share this same latent bug if the sort is ever
/// dropped: an unsorted list would pair each marker with whatever
/// happens to sit next to it in the original order, not its real
/// chronological neighbor.
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
  return chapters;
}
