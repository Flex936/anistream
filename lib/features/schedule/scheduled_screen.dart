import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../core/theme/app_palette.dart';
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

  static const List<String> _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

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
    super.dispose();
  }

  void _reload() => setState(() => _animeFuture = _api.getCurrentlyAiring());

  Map<String, List<Anime>> _buildCalendar(List<Anime> anime) {
    final grid = {for (final day in _days) day: <Anime>[]};

    final active = anime.where((a) => a.nextAiringEpisode != null).toList()
      ..sort((a, b) => a.nextAiringEpisode!.airingAt.compareTo(b.nextAiringEpisode!.airingAt));

    for (final item in active) {
      final airDate = DateTime.fromMillisecondsSinceEpoch(item.nextAiringEpisode!.airingAt * 1000);
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
    return 'Airing now / Aired';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Anime>>(
      future: _animeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 96),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary)),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 96),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: _ErrorPane(error: snapshot.error, onRetry: _reload),
                ),
              ],
            ),
          );
        }

        final calendar = _buildCalendar(snapshot.data ?? []);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 96),
              const Padding(
                padding: EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weekly Anime Schedule', style: TextStyle(color: AppPalette.textMain, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    SizedBox(height: 4),
                    Text('Times are automatically adjusted to your local timezone.', style: TextStyle(color: AppPalette.textMuted, fontSize: 13)),
                  ],
                ),
              ),
              _buildGrid(calendar),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid(Map<String, List<Anime>> calendar) {
    final todayIndex = _now.weekday - 1; 

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const hPad = 32.0;
        const bPad = 24.0;
        final available = constraints.maxWidth - 2 * hPad;
        final naturalWidth = (available - 6 * gap) / 7;
        final colWidth = naturalWidth.clamp(148.0, double.infinity);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(hPad, 0, hPad, bPad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(_days.length, (i) {
              return Padding(
                padding: EdgeInsets.only(right: i < _days.length - 1 ? gap : 0),
                child: _DayColumn(
                  day: _days[i],
                  items: calendar[_days[i]]!,
                  width: colWidth,
                  isToday: i == todayIndex,
                  formatLocalTime: _formatLocalTime,
                  getTimeRemaining: _getTimeRemaining,
                  onSelectAnime: widget.onSelectAnime,
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _DayColumn extends StatelessWidget {
  final String day;
  final List<Anime> items;
  final double width;
  final bool isToday;
  final String Function(int) formatLocalTime;
  final String Function(int) getTimeRemaining;
  final ValueChanged<Anime>? onSelectAnime;

  const _DayColumn({
    required this.day,
    required this.items,
    required this.width,
    required this.isToday,
    required this.formatLocalTime,
    required this.getTimeRemaining,
    this.onSelectAnime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isToday ? AppPalette.primary.withValues(alpha: 0.40) : AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min, 
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Row(
              children: [
                Text(day, style: TextStyle(color: isToday ? AppPalette.primary : AppPalette.textMain, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppPalette.overlay, borderRadius: BorderRadius.circular(10)),
                  child: Text('${items.length}', style: const TextStyle(color: AppPalette.textMuted, fontSize: 9, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1, color: AppPalette.border),
          const SizedBox(height: 6),

          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No releases', style: TextStyle(color: AppPalette.textMuted, fontSize: 10, fontStyle: FontStyle.italic))),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    GestureDetector(
                      onTap: () => onSelectAnime?.call(items[i]),
                      child: CalendarCard(
                        anime: items[i],
                        formatLocalTime: formatLocalTime,
                        getTimeRemaining: getTimeRemaining,
                      ),
                    ),
                    if (i < items.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorPane({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppPalette.textMuted, size: 52),
          const SizedBox(height: 16),
          const Text('Could not load schedule', style: TextStyle(color: AppPalette.textMain, fontSize: 17, fontWeight: FontWeight.w600)),
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
            style: OutlinedButton.styleFrom(foregroundColor: AppPalette.primary, side: const BorderSide(color: AppPalette.primary)),
          ),
        ],
      ),
    );
  }
}