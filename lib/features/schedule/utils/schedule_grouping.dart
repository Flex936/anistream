import '../../../data/anilist/models/anime.dart';

const List<String> weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Groups currently-airing anime by the weekday their next episode airs on,
/// in the viewer's local timezone. Pulled out of
/// `_ScheduledScreenState._buildCalendar` — pure data transformation with no
/// business being a State method.
Map<String, List<Anime>> groupByWeekday(List<Anime> anime) {
  final grid = {for (final day in weekdays) day: <Anime>[]};

  final active = anime.where((a) => a.nextAiringEpisode != null).toList()
    ..sort(
      (a, b) => a.nextAiringEpisode!.airingAt.compareTo(
        b.nextAiringEpisode!.airingAt,
      ),
    );

  for (final item in active) {
    final airDate = DateTime.fromMillisecondsSinceEpoch(
      item.nextAiringEpisode!.airingAt * 1000,
    );
    final idx = airDate.weekday - 1;
    if (idx >= 0 && idx < weekdays.length) {
      grid[weekdays[idx]]!.add(item);
    }
  }
  return grid;
}
