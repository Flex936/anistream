import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/models/anime.dart';
import '../../shared/utils/perf_animations.dart';
import '../../shared/utils/responsive_grid.dart';
import '../../shared/widgets/hover_focus_builder.dart';
import 'controllers/watchlist_controller.dart';
import 'widgets/watchlist_cards.dart';

class WatchlistScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const WatchlistScreen({super.key, this.onSelectAnime});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  late final WatchlistController _controller;
  final ScrollController _scrollController = ScrollController();

  bool _isListView = false;

  // ── Was a plain `String? _hoveredBanner` field driven by setState() on
  // this entire State — hovering any single card in a 36-item grid was
  // rebuilding the whole screen, including the CustomScrollView's slivers.
  // As a ValueNotifier, only the small ValueListenableBuilder wrapping the
  // background image below rebuilds on hover; the grid/list never does. ──
  final ValueNotifier<String?> _hoveredBanner = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _controller = WatchlistController();
    _scrollController.addListener(_onScroll);
    _controller.loadInitial();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _hoveredBanner.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      _controller.fetchNextForActiveTab();
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

  void _handleHover(String? bannerUrl, bool isHovered) {
    if (isHovered && bannerUrl != null) {
      _hoveredBanner.value = bannerUrl;
    } else if (!isHovered && _hoveredBanner.value == bannerUrl) {
      _hoveredBanner.value = null;
    }
  }

  Widget _buildEmptyState(String activeStatus) {
    return switch (activeStatus) {
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
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Stack(
          children: [
            // ── Hover-driven background: isolated behind a
            // ValueListenableBuilder so hovering a card only rebuilds this
            // small subtree, never the grid/list below it. ──
            Positioned.fill(
              child: ValueListenableBuilder<String?>(
                valueListenable: _hoveredBanner,
                builder: (context, hoveredBanner, _) {
                  return AnimatedSwitcher(
                    // ── Zero-duration under Performant mode — the backdrop
                    // swap still happens, it just snaps instead of
                    // dissolving, avoiding the extra composited frames a
                    // 600ms cross-fade of a full-screen image would
                    // otherwise cost. ──
                    duration: perfDuration(
                      uiPerformanceMode,
                      const Duration(milliseconds: 600),
                    ),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child:
                        (hoveredBanner != null &&
                            hoveredBanner.trim().isNotEmpty)
                        ? Stack(
                            key: ValueKey(hoveredBanner),
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                hoveredBanner,
                                fit: BoxFit.cover,
                                // ── cacheWidth added: this is a
                                // full-screen backdrop that's immediately
                                // heavily blurred (or fully covered in
                                // performance mode) — decoding it at full
                                // network resolution bought nothing. ──
                                cacheWidth: 400,
                                errorBuilder: (context, error, stackTrace) =>
                                    const ColoredBox(color: AppPalette.base),
                              ),
                              if (uiPerformanceMode)
                                Container(
                                  color: AppPalette.base.withValues(
                                    alpha: 0.90,
                                  ),
                                )
                              else
                                BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 50,
                                    sigmaY: 50,
                                  ),
                                  child: Container(
                                    color: AppPalette.base.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  );
                },
              ),
            ),

            Positioned.fill(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                      child: Wrap(
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
                                      active:
                                          _controller.activeStatus == 'CURRENT',
                                      onTap: () =>
                                          _controller.switchTab('CURRENT'),
                                    ),
                                    _TabButton(
                                      icon: Icons.calendar_today_outlined,
                                      label: 'Planning',
                                      active:
                                          _controller.activeStatus ==
                                          'PLANNING',
                                      onTap: () =>
                                          _controller.switchTab('PLANNING'),
                                    ),
                                    _TabButton(
                                      icon: Icons.check_circle_outline_rounded,
                                      label: 'Watched',
                                      active:
                                          _controller.activeStatus ==
                                          'COMPLETED',
                                      onTap: () =>
                                          _controller.switchTab('COMPLETED'),
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

                  if (_controller.isInitialLoading)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: const _LoadingPane(),
                      ),
                    )
                  else if (_controller.error != null)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: _ErrorPane(
                          message: _controller.error!,
                          onRetry: _controller.refreshActiveTab,
                        ),
                      ),
                    )
                  else if (_controller.activeEntries.isEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: _buildEmptyState(_controller.activeStatus),
                      ),
                    )
                  else
                    _isListView
                        ? _buildListLayout(uiPerformanceMode)
                        : _buildGridLayout(uiPerformanceMode),

                  if (_controller.isFetchingNext)
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
      },
    );
  }

  Widget _buildGridLayout(bool uiPerformanceMode) {
    final activeStatus = _controller.activeStatus;
    final activeEntries = _controller.activeEntries;
    final isWatching = activeStatus == 'CURRENT';

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cols = isWatching
            ? landscapeGridColumns(constraints.crossAxisExtent)
            : verticalGridColumns(constraints.crossAxisExtent);
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
              final entry = activeEntries[i];
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
                    uiPerformanceMode: uiPerformanceMode,
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
                    listStatus: activeStatus,
                    showProgress: false,
                    uiPerformanceMode: uiPerformanceMode,
                    onTap: () => widget.onSelectAnime?.call(entry.media),
                    onHover: (hovered) => _handleHover(hoverImage, hovered),
                  ),
                );
              }
            }, childCount: activeEntries.length),
          ),
        );
      },
    );
  }

  Widget _buildListLayout(bool uiPerformanceMode) {
    final activeStatus = _controller.activeStatus;
    final activeEntries = _controller.activeEntries;

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
                entry: activeEntries[i],
                autofocus: i == 0,
                showProgress: activeStatus == 'CURRENT',
                uiPerformanceMode: uiPerformanceMode,
                onTap: () => widget.onSelectAnime?.call(activeEntries[i].media),
                onHover: (hovered) => _handleHover(
                  activeEntries[i].media.bannerImage ??
                      activeEntries[i].media.coverImage?.display,
                  hovered,
                ),
              ),
            ),
          );
        }, childCount: activeEntries.length),
      ),
    );
  }
}

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
