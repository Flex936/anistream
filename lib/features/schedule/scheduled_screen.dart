import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import 'utils/schedule_grouping.dart';
import 'widgets/calendar_card.dart';

class ScheduledScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const ScheduledScreen({super.key, this.onSelectAnime});

  @override
  State<ScheduledScreen> createState() => _ScheduledScreenState();
}

class _ScheduledScreenState extends State<ScheduledScreen> {
  late final AnilistQueryService _api;
  late Future<List<Anime>> _animeFuture;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  final ScrollController _scrollController = ScrollController();

  // Memoization for groupByWeekday. _animeFuture is only ever reassigned
  // by _reload() — the once-a-minute clock tick just calls setState(() =>
  // _now = ...), leaving _animeFuture (and therefore FutureBuilder's
  // resolved snapshot.data instance) untouched. That means the same
  // List<Anime> reference comes back on every tick, so identical()
  // reliably tells us "nothing to regroup" without needing to compare
  // contents — avoiding a full sort+bucket over the entire airing list
  // purely to refresh "Xh Ym left" labels.
  List<Anime>? _cachedSourceList;
  Map<String, List<Anime>>? _cachedCalendar;

  @override
  void initState() {
    super.initState();
    _api = AnilistQueryService();
    _animeFuture = _api.getCurrentlyAiring();

    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _api.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _animeFuture = _api.getCurrentlyAiring());

  /// Returns the cached weekday grouping if [source] is the same list
  /// instance last grouped, otherwise regroups and caches the result.
  Map<String, List<Anime>> _calendarFor(List<Anime> source) {
    if (identical(source, _cachedSourceList) && _cachedCalendar != null) {
      return _cachedCalendar!;
    }
    final grouped = groupByWeekday(source);
    _cachedSourceList = source;
    _cachedCalendar = grouped;
    return grouped;
  }

  String _formatLocalTime(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _getTimeRemaining(int timestamp) {
    final target = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final diff = target.difference(_now);

    if (!diff.isNegative && diff.inSeconds > 0) {
      final d = diff.inDays;
      final h = diff.inHours.remainder(24);
      final m = diff.inMinutes.remainder(60);
      if (d > 0) return '${d}d ${h}h left';
      if (h > 0) return '${h}h ${m}m left';
      if (m > 0) return '${m}m left';
    }
    return 'Airing now';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final hPad = isMobile ? 16.0 : 32.0;
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    final typography = context.appTypography;

    return FutureBuilder<List<Anime>>(
      future: _animeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: _ErrorPane(error: snapshot.error, onRetry: _reload),
          );
        }

        // const <Anime>[] rather than a fresh [] literal: the const
        // literal is canonicalized, so if this fallback is ever hit
        // twice in a row, identical() below still recognizes it as the
        // same instance and the cache stays warm.
        final sourceList = snapshot.data ?? const <Anime>[];
        final calendar = _calendarFor(sourceList);

        // Reorders days to start with "Today".
        final todayIdx = _now.weekday - 1;
        final orderedDays = [
          ...weekdays.sublist(todayIdx),
          ...weekdays.sublist(0, todayIdx),
        ];

        return SingleChildScrollView(
          controller: _scrollController,
          // Top 96px navbar clearance lives in the scroll view's own
          // padding rather than as a sibling widget — same convention as
          // home_screen.dart, per dpad's shelf-layout padding rule.
          padding: const EdgeInsets.only(top: 96, bottom: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule',
                      style: typography.screenTitle.copyWith(
                        color: AppPalette.textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Automatically adjusted to your local timezone.',
                      style: TextStyle(
                        color: AppPalette.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              for (int i = 0; i < orderedDays.length; i++) ...[
                Builder(
                  builder: (context) {
                    final dayName = orderedDays[i];
                    final items = calendar[dayName]!;

                    if (items.isEmpty) return const SizedBox.shrink();

                    String displayTitle = dayName;
                    if (i == 0) {
                      displayTitle = 'Today';
                    } else if (i == 1) {
                      displayTitle = 'Tomorrow';
                    }

                    return _DayShelf(
                      // The stable weekday name, not displayTitle —
                      // "Today"/"Tomorrow" describe the same underlying
                      // weekday differently depending on the current
                      // date, which would fragment the shelf's own
                      // memory key across the daily rollover. dayName
                      // never changes regardless of what today is.
                      regionKey: dayName,
                      title: displayTitle,
                      items: items,
                      hPad: hPad,
                      formatLocalTime: _formatLocalTime,
                      getTimeRemaining: _getTimeRemaining,
                      onSelectAnime: widget.onSelectAnime,
                      uiPerformanceMode: uiPerformanceMode,
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// Horizontal carousel shelf.
class _DayShelf extends StatelessWidget {
  final String regionKey;
  final String title;
  final List<Anime> items;
  final double hPad;
  final String Function(int) formatLocalTime;
  final String Function(int) getTimeRemaining;
  final ValueChanged<Anime>? onSelectAnime;
  final bool uiPerformanceMode;

  const _DayShelf({
    required this.regionKey,
    required this.title,
    required this.items,
    required this.hPad,
    required this.formatLocalTime,
    required this.getTimeRemaining,
    this.onSelectAnime,
    required this.uiPerformanceMode,
  });

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;
    final cardSizes = context.appCardSizes;
    // Same width-driven-poster + fixed-text-block calculation
    // AnimeCarousel uses, keeping every shelf's height in sync with the
    // shared card-sizing tokens.
    final shelfHeight =
        cardSizes.shelfWidth / cardSizes.posterAspectRatio +
        CalendarCard.kTextBlockHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style: typography.dayShelfTitle.copyWith(
                  color: AppPalette.textMain,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${items.length} releases',
                style: typography.metaLabel.copyWith(
                  color: AppPalette.textMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: shelfHeight,
          // DpadRegion: this shelf is its own visual section, matching
          // the Home carousels' convention. memoryKey uses the stable
          // regionKey (weekday name) so the last-focused card in a given
          // day's row survives both the once-a-minute clock-driven
          // rebuild and a full leave-and-return trip through
          // Search/Watchlist/Home. No edge-behavior overrides — default
          // leave is what lets Up escape to the navbar from the topmost
          // shelf, and cascades between shelves the same way Home's
          // carousels do.
          child: DpadRegion(
            memoryKey: 'schedule.$regionKey',
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                return SizedBox(
                  // Stable per-anime identity across rebuilds: this key
                  // guarantees the CalendarCard at a given index is
                  // reliably the same anime's Element/State across a
                  // rebuild, complementing DpadRegion's own memoryKey
                  // (which remembers which index was focused).
                  key: ValueKey(items[i].id),
                  width: cardSizes.shelfWidth,
                  child: CalendarCard(
                    anime: items[i],
                    formatLocalTime: formatLocalTime,
                    getTimeRemaining: getTimeRemaining,
                    onTap: () => onSelectAnime?.call(items[i]),
                    uiPerformanceMode: uiPerformanceMode,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorPane({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.wifi_off_rounded,
          color: AppPalette.textMuted,
          size: 52,
        ),
        const SizedBox(height: 16),
        const Text(
          'Could not load schedule',
          style: TextStyle(
            color: AppPalette.textMain,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          // This text can wrap up to 3 lines. cardSummary's height: 1.4
          // would visibly change line-spacing on wrapped text here, so
          // it's left as a plain literal rather than routed through that
          // token.
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.textMuted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppPalette.primary,
            side: const BorderSide(color: AppPalette.primary),
          ),
        ),
      ],
    );
  }
}
