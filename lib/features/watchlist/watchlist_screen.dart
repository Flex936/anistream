import 'dart:ui';
import 'package:flutter/material.dart';

import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/media_list.dart';
import '../../data/anilist/models/anime.dart';
import '../../core/theme/app_palette.dart';
import '../../shared/widgets/hover_focus_builder.dart';
import 'widgets/watchlist_cards.dart';

class WatchlistScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const WatchlistScreen({super.key, this.onSelectAnime});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final AnilistQueryService _api = AnilistQueryService();
  final ScrollController _scrollController = ScrollController();

  final Map<String, List<MediaListEntry>> _entries = {
    'CURRENT': [],
    'PLANNING': [],
    'COMPLETED': [],
  };
  final Map<String, int> _pages = {'CURRENT': 1, 'PLANNING': 1, 'COMPLETED': 1};
  final Map<String, bool> _hasNext = {
    'CURRENT': true,
    'PLANNING': true,
    'COMPLETED': true,
  };

  bool _initialLoading = true;
  bool _fetchingNext = false;
  String? _error;
  String _activeStatus = 'CURRENT';

  bool _isListView = false;
  String? _hoveredBanner;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchTab(_activeStatus);
  }

  @override
  void dispose() {
    _api.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      if (!_initialLoading && !_fetchingNext && _hasNext[_activeStatus]!) {
        _fetchTab(_activeStatus);
      }
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _fetchTab(String status, {bool refresh = false}) async {
    if (refresh) {
      _pages[status] = 1;
      _hasNext[status] = true;
      _entries[status] = [];
    }

    if (!_hasNext[status]!) return;

    setState(() {
      if (_entries[status]!.isEmpty) {
        _initialLoading = true;
        _error = null;
      } else {
        _fetchingNext = true;
      }
    });

    try {
      final result = await _api.getUserWatchlist(
        status: status,
        page: _pages[status]!,
        perPage: 36,
      );

      if (mounted) {
        // ── Local Deduplication ──
        final existingIds = _entries[status]!.map((e) => e.media.id).toSet();
        final newUniqueEntries = result.entries
            .where((e) => !existingIds.contains(e.media.id))
            .toList();

        setState(() {
          _entries[status]!.addAll(newUniqueEntries);
          _hasNext[status] = result.hasNextPage;
          _pages[status] = _pages[status]! + 1;
          _initialLoading = false;
          _fetchingNext = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _initialLoading = false;
          _fetchingNext = false;
        });
      }
    }
  }

  void _switchTab(String newStatus) {
    if (_activeStatus == newStatus) return;
    setState(() => _activeStatus = newStatus);

    if (_entries[newStatus]!.isEmpty && _hasNext[newStatus]!) {
      _fetchTab(newStatus);
    }
  }

  List<MediaListEntry> get _activeEntries => _entries[_activeStatus] ?? [];

  int _verticalColumns(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    if (width < 1500) return 5;
    return 6;
  }

  int _landscapeColumns(double width) {
    if (width < 600) return 1;
    if (width < 900) return 2;
    if (width < 1200) return 3;
    if (width < 1500) return 4;
    return 5;
  }

  void _handleHover(String? bannerUrl, bool isHovered) {
    if (isHovered && bannerUrl != null) {
      setState(() => _hoveredBanner = bannerUrl);
    } else if (!isHovered && _hoveredBanner == bannerUrl) {
      setState(() => _hoveredBanner = null);
    }
  }

  Widget _buildEmptyState() {
    return switch (_activeStatus) {
      'CURRENT' => const _EmptyPane(
        icon: Icons.play_circle_outline_rounded,
        title: 'No Active Shows',
        subtitle: 'Start watching something to see it here.',
      ),
      'PLANNING' => const _EmptyPane(
        icon: Icons.bookmark_outline_rounded,
        title: 'Empty Planner',
        subtitle: 'Queue up some anime for later.',
      ),
      _ => const _EmptyPane(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing Completed',
        subtitle: 'Finish a series to add it to your collection.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background banner (no changes needed)
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: (_hoveredBanner != null && _hoveredBanner!.trim().isNotEmpty)
                ? Stack(
                    key: ValueKey(_hoveredBanner),
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _hoveredBanner!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(color: AppPalette.base),
                      ),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                        child: Container(
                          color: AppPalette.base.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),

        // ── Total Sliver Implementation ──
        Positioned.fill(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 96)),

              // Title and Tabs
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      const Text(
                        'My Library',
                        style: TextStyle(
                          color: AppPalette.textMain,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppPalette.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppPalette.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.grid_view_rounded,
                                    size: 20,
                                    color: !_isListView
                                        ? AppPalette.primary
                                        : AppPalette.textMuted,
                                  ),
                                  onPressed: () =>
                                      setState(() => _isListView = false),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.view_list_rounded,
                                    size: 20,
                                    color: _isListView
                                        ? AppPalette.primary
                                        : AppPalette.textMuted,
                                  ),
                                  onPressed: () =>
                                      setState(() => _isListView = true),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppPalette.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppPalette.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _TabButton(
                                  icon: Icons.play_arrow_rounded,
                                  label: 'Watching',
                                  active: _activeStatus == 'CURRENT',
                                  onTap: () => _switchTab('CURRENT'),
                                ),
                                _TabButton(
                                  icon: Icons.calendar_today_outlined,
                                  label: 'Planning',
                                  active: _activeStatus == 'PLANNING',
                                  onTap: () => _switchTab('PLANNING'),
                                ),
                                _TabButton(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: 'Watched',
                                  active: _activeStatus == 'COMPLETED',
                                  onTap: () => _switchTab('COMPLETED'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Content States
              if (_initialLoading)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: const _LoadingPane(),
                  ),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: _ErrorPane(
                      message: _error!,
                      onRetry: () => _fetchTab(_activeStatus, refresh: true),
                    ),
                  ),
                )
              else if (_activeEntries.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: _buildEmptyState(),
                  ),
                )
              else
                _isListView ? _buildListLayout() : _buildGridLayout(),

              // Loading Indicator at the bottom
              if (_fetchingNext)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppPalette.primary,
                        ),
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridLayout() {
    final isWatching = _activeStatus == 'CURRENT';

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cols = isWatching
            ? _landscapeColumns(constraints.crossAxisExtent)
            : _verticalColumns(constraints.crossAxisExtent);
        final aspectRatio = isWatching ? 1.77 : 0.52;

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 20,
              mainAxisSpacing: 24,
              childAspectRatio: aspectRatio,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final entry = _activeEntries[i];
              final hoverImage =
                  entry.media.bannerImage ?? entry.media.coverImage?.display;

              if (isWatching) {
                return Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (f) {
                    if (f && i < cols) _scrollToTop();
                  },
                  child: HeroCard(
                    entry: entry,
                    autofocus: i == 0,
                    onTap: () => widget.onSelectAnime?.call(entry.media),
                    onHover: (hovered) => _handleHover(hoverImage, hovered),
                  ),
                );
              } else {
                return Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (f) {
                    if (f && i < cols || i == 0) _scrollToTop();
                  },
                  child: WatchlistCard(
                    entry: entry,
                    autofocus: i == 0,
                    listStatus: _activeStatus,
                    showProgress: false,
                    onTap: () => widget.onSelectAnime?.call(entry.media),
                    onHover: (hovered) => _handleHover(hoverImage, hovered),
                  ),
                );
              }
            }, childCount: _activeEntries.length),
          ),
        );
      },
    );
  }

  Widget _buildListLayout() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (f) {
                if (f && i == 0) _scrollToTop();
              },
              child: ListCard(
                entry: _activeEntries[i],
                autofocus: i == 0,
                showProgress: _activeStatus == 'CURRENT',
                onTap: () =>
                    widget.onSelectAnime?.call(_activeEntries[i].media),
                onHover: (hovered) => _handleHover(
                  _activeEntries[i].media.bannerImage ??
                      _activeEntries[i].media.coverImage?.display,
                  hovered,
                ),
              ),
            ),
          );
        }, childCount: _activeEntries.length),
      ),
    );
  }
}

// ── Private sub-widgets for Screen ──

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      onTap: onTap,
      builder: (context, hovered) {
        final bgColor = active
            ? AppPalette.primary
            : (hovered
                  ? AppPalette.white.withValues(alpha: 0.08)
                  : AppPalette.transparent);
        final contentColor = active
            ? AppPalette.white
            : (hovered ? AppPalette.textMain : AppPalette.textMuted);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppPalette.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: contentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: contentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary),
      strokeWidth: 2.5,
    ),
  );
}

class _EmptyPane extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyPane({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(32, 0, 32, 32),
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppPalette.border,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppPalette.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: AppPalette.textMain,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: AppPalette.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorPane({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppPalette.textMuted,
            size: 52,
          ),
          const SizedBox(height: 16),
          const Text(
            'Could not load watchlist',
            style: TextStyle(
              color: AppPalette.textMain,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
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
      ),
    );
  }
}
