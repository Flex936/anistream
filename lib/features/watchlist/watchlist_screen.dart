import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/models/anime.dart';
import '../../shared/utils/perf_animations.dart';
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

  // A ValueNotifier rather than plain State, so hovering a single card in
  // a 36-item grid only rebuilds the small ValueListenableBuilder wrapping
  // the background image below, not the whole screen (including the
  // CustomScrollView's slivers).
  final ValueNotifier<String?> _hoveredBanner = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _controller = WatchlistController();
    _scrollController.addListener(_onScroll);
    unawaited(_controller.loadInitial());
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
      unawaited(_controller.fetchNextForActiveTab());
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
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

    final typography = context.appTypography;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Stack(
          children: [
            // Hover-driven background, isolated behind a
            // ValueListenableBuilder so hovering a card only rebuilds
            // this small subtree, never the grid/list below it.
            Positioned.fill(
              child: ValueListenableBuilder<String?>(
                valueListenable: _hoveredBanner,
                builder: (context, hoveredBanner, _) {
                  return AnimatedSwitcher(
                    // Zero-duration under Performant mode — the backdrop
                    // swap still happens, it just snaps instead of
                    // dissolving, avoiding the extra composited frames a
                    // 600ms cross-fade of a full-screen image would
                    // otherwise cost.
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
                                // A full-screen backdrop that's
                                // immediately heavily blurred (or fully
                                // covered in performance mode), so
                                // decoding at full network resolution
                                // buys nothing.
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
                          Text(
                            'My Library',
                            style: typography.sectionTitle.copyWith(
                              color: AppPalette.textMain,
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
    final cardSizes = context.appCardSizes;

    final double maxCrossAxisExtent = isWatching
        ? cardSizes.heroGridMaxWidth
        : cardSizes.gridMaxWidth;

    final SliverGridDelegateWithMaxCrossAxisExtent gridDelegate = isWatching
        ? SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossAxisExtent,
            crossAxisSpacing: 20,
            mainAxisSpacing: 24,
            // HeroCard has no separate text block below the art — every
            // pixel of its box is the Stack.expand poster/overlay
            // itself — so a plain childAspectRatio is exact at any
            // column width, unlike the offset-height calculation the
            // poster-card branch below needs.
            childAspectRatio: 16 / 9,
          )
        : SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossAxisExtent,
            crossAxisSpacing: 20,
            mainAxisSpacing: 24,
            // See SearchResultsScreen's identical calculation —
            // WatchlistCard shares the same width-driven-poster-plus-
            // fixed-text-block shape as AnimeCard.
            mainAxisExtent:
                cardSizes.gridMaxWidth / cardSizes.posterAspectRatio +
                WatchlistCard.kTextBlockHeight,
          );

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // Mirrors SliverGridDelegateWithMaxCrossAxisExtent's own
        // column-count formula — used only to know which items sit in
        // the first visual row, so focusing one of them scrolls it clear
        // of the pinned nav bar. The grid's actual sizing comes from
        // gridDelegate above, not from this value.
        final cols = (constraints.crossAxisExtent / (maxCrossAxisExtent + 20))
            .ceil()
            .clamp(1, activeEntries.length);

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          sliver: SliverGrid(
            gridDelegate: gridDelegate,
            delegate: SliverChildBuilderDelegate((context, i) {
              final entry = activeEntries[i];
              final hoverImage =
                  entry.media.bannerImage ?? entry.media.coverImage?.display;

              // Keyed by anime id in both branches: PLANNING <-> COMPLETED stays
              // on the same card type (WatchlistCard), so without a key the
              // Focus/DpadFocusable Element is reused by position across a tab
              // switch and `autofocus: i == 0` never refires. (CURRENT switches
              // happen to self-correct, since the card type itself changes
              // between HeroCard and WatchlistCard — but keying unconditionally
              // is simpler than relying on that as the mechanism.)
              if (isWatching) {
                return Focus(
                  key: ValueKey(entry.media.id),
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
                  key: ValueKey(entry.media.id),
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
          // Keyed by anime id — every tab (CURRENT/PLANNING/COMPLETED) uses
          // the same ListCard type here, so any tab switch reuses this
          // Padding/Focus/ListCard by position without a key, and
          // `autofocus: i == 0` never refires on the new top item.
          return Padding(
            key: ValueKey(activeEntries[i].media.id),
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
    final typography = context.appTypography;

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
              // cardTitleCompact (13/w600) is reused here for the tab
              // label — the token's height is inconsequential for a
              // single line of text; see app_typography.dart's class doc
              // comment on token-name drift.
              Text(
                label,
                style: typography.cardTitleCompact.copyWith(
                  color: contentColor,
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
    final typography = context.appTypography;

    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(32, 0, 32, 32),
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppPalette.textMuted, size: 48),
            const SizedBox(height: 16),
            // cardTitleProminent is reused here — see
            // app_typography.dart's class doc comment on token-name drift.
            Text(
              title,
              style: typography.cardTitleProminent.copyWith(
                color: AppPalette.textMain,
              ),
            ),
            const SizedBox(height: 6),
            // This subtitle can wrap depending on content/screen width;
            // cardSummary's height would visibly change line-spacing on
            // wrapped text, so it's left as a plain literal.
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
            // A dynamic, potentially long error message — same
            // multi-line height caution as scheduled_screen.dart's
            // _ErrorPane.
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
