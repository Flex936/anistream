import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_service.dart';
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

  bool _uiPerformanceMode = false;

  static const List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _api = AnilistQueryService();
    _animeFuture = _api.getCurrentlyAiring();

    // ── Load Performance Setting ──
    SettingsService().load().then((s) {
      if (mounted) setState(() => _uiPerformanceMode = s.uiPerformanceMode);
    });

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

  Map<String, List<Anime>> _buildCalendar(List<Anime> anime) {
    final grid = {for (final day in _days) day: <Anime>[]};

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
      if (idx >= 0 && idx < _days.length) {
        grid[_days[idx]]!.add(item);
      }
    }
    return grid;
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
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hPad = isMobile ? 16.0 : 32.0;

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

        final calendar = _buildCalendar(snapshot.data ?? []);

        // ── Reorder days to start with "Today" ──
        final todayIdx = _now.weekday - 1;
        final orderedDays = [
          ..._days.sublist(todayIdx),
          ..._days.sublist(0, todayIdx),
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
                        fontSize: 32, // Apple-style large header
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

              // ── Stack Horizontal Shelves Vertically ──
              for (int i = 0; i < orderedDays.length; i++) ...[
                Builder(
                  builder: (context) {
                    final dayName = orderedDays[i];
                    final items = calendar[dayName]!;

                    // Hide days with no anime releases to keep the UI clean
                    if (items.isEmpty) return const SizedBox.shrink();

                    // Dynamic naming for Apple-style UX
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
                      uiPerformanceMode: _uiPerformanceMode,
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
          height:
              260, // Fixed height specifically tuned for a 2/3 aspect ratio card + text
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              return SizedBox(
                width: 130, // Excellent width for mobile and TV grids
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
