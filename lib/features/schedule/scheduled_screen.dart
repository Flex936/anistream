import 'dart:async';

import 'package:flutter/material.dart';

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

  // ── Memoization for groupByWeekday. _animeFuture is only ever reassigned
  // by _reload() — the once-a-minute clock tick just calls setState(() =>
  // _now = ...), leaving _animeFuture (and therefore FutureBuilder's
  // resolved snapshot.data instance) untouched. That means the SAME
  // List<Anime> reference comes back on every single tick, so identical()
  // reliably tells us "nothing to regroup" without needing to compare
  // contents. Previously every tick re-ran a full sort+bucket over the
  // entire airing list purely to refresh "Xh Ym left" labels. ──
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
  /// instance we last grouped, otherwise regroups and caches the result.
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

        // ── const <Anime>[] rather than a fresh [] literal: if this
        // fallback were ever hit twice in a row, a `[]` literal would
        // create a NEW empty list each time (never identical() to the
        // last one), permanently defeating the cache. The const literal
        // is canonicalized, so even this edge case stays memoized. ──
        final sourceList = snapshot.data ?? const <Anime>[];
        final calendar = _calendarFor(sourceList);

        // ── Reorder days to start with "Today" ──
        final todayIdx = _now.weekday - 1;
        final orderedDays = [
          ...weekdays.sublist(todayIdx),
          ...weekdays.sublist(0, todayIdx),
        ];

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 96),
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule',
                      style: TextStyle(
                        color: AppPalette.textMain,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.0,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
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

// ── Horizontal Carousel Shelf ──
class _DayShelf extends StatelessWidget {
  final String title;
  final List<Anime> items;
  final double hPad;
  final String Function(int) formatLocalTime;
  final String Function(int) getTimeRemaining;
  final ValueChanged<Anime>? onSelectAnime;
  final bool uiPerformanceMode;

  const _DayShelf({
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
                style: const TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${items.length} releases',
                style: const TextStyle(
                  color: AppPalette.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 300,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              return SizedBox(
                width: 160,
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
