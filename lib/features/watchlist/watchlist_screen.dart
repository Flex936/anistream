import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/models/anime.dart';
import '../../shared/utils/perf_animations.dart';
import '../../shared/widgets/app_segmented_control.dart';
import 'controllers/watchlist_controller.dart';
import 'widgets/watchlist_cards.dart';

class WatchlistScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const WatchlistScreen({super.key, this.onSelectAnime});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _HoverTarget {
  final String url;
  const _HoverTarget(this.url);
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  late final WatchlistController _controller;
  final ScrollController _scrollController = ScrollController();

  bool _isListView = false;

  // Persisted the same way TheaterControls/MobileTheaterControls persist
  // volume ('theater_volume') — a direct SharedPreferencesAsync key rather
  // than a field on AppSettings, since this is a per-screen UI preference,
  // not something exposed in the Settings menu.
  static const String _kListViewPrefKey = 'watchlist_list_view';
  final _prefs = SharedPreferencesAsync();

  // A ValueNotifier rather than plain State, so hovering a single card in
  // a 36-item grid only rebuilds the small ValueListenableBuilder wrapping
  // the background image below, not the whole screen (including the
  // CustomScrollView's slivers). Wrapped in `_HoverTarget` rather than a
  // bare `String?` so every commit is a distinct object even when the URL
  // repeats — `AnimatedSwitcher` keys its outgoing/incoming children by
  // this value, and re-hovering the same card before the previous
  // cross-fade finished exiting would otherwise hand it a duplicate key.
  final ValueNotifier<_HoverTarget?> _hoveredBanner =
      ValueNotifier<_HoverTarget?>(null);

  // Coalesces rapid hover in/out churn (a fast mouse sweep across the
  // grid) into a single backdrop commit once the pointer settles, rather
  // than firing a new cross-fade per card boundary crossed.
  Timer? _hoverDebounceTimer;
  String? _pendingHoverUrl;
  static const _hoverDebounceDelay = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    _controller = WatchlistController();
    _scrollController.addListener(_onScroll);
    unawaited(_controller.loadInitial());
    // initState can't be async — _loadListViewPreference() returns
    // Future<void>, so the fire-and-forget intent is made explicit
    // instead of silently dropped (unawaited_futures). The method itself
    // guards its own setState with a `mounted` check.
    unawaited(_loadListViewPreference());
  }

  Future<void> _loadListViewPreference() async {
    final saved = await _prefs.getBool(_kListViewPrefKey);
    if (mounted && saved != null) {
      setState(() => _isListView = saved);
    }
  }

  void _setListView(bool value) {
    setState(() => _isListView = value);
    unawaited(_prefs.setBool(_kListViewPrefKey, value));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _hoverDebounceTimer?.cancel();
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
    // Same stale-leave guard as before (only clear if this card is the
    // one currently claiming hover) — just tracked against the pending
    // intent instead of the already-committed value, since commits now
    // lag behind intent by `_hoverDebounceDelay`.
    if (isHovered && bannerUrl != null) {
      _pendingHoverUrl = bannerUrl;
    } else if (!isHovered && _pendingHoverUrl == bannerUrl) {
      _pendingHoverUrl = null;
    } else {
      return;
    }

    _hoverDebounceTimer?.cancel();
    final target = _pendingHoverUrl;
    _hoverDebounceTimer = Timer(_hoverDebounceDelay, () {
      if (!mounted) return;
      _hoveredBanner.value = target == null ? null : _HoverTarget(target);
    });
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
              child: ValueListenableBuilder<_HoverTarget?>(
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
                            hoveredBanner.url.trim().isNotEmpty)
                        ? Stack(
                            // Keyed by object identity, not the URL
                            // string — see `_hoveredBanner`'s doc
                            // comment above. A fresh `_HoverTarget` is
                            // constructed on every commit, so
                            // AnimatedSwitcher can never be asked to
                            // reconcile two siblings sharing a key, even
                            // when re-hovering the same card back-to-back.
                            key: ObjectKey(hoveredBanner),
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                hoveredBanner.url,
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
                                      onPressed: () => _setListView(false),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.view_list_rounded,
                                        size: 20,
                                        color: _isListView
                                            ? AppPalette.primary
                                            : AppPalette.textMuted,
                                      ),
                                      onPressed: () => _setListView(true),
                                    ),
                                  ],
                                ),
                              ),
                              AppSegmentedControl<String>(
                                items: const [
                                  AppSegmentedControlItem(
                                    value: 'CURRENT',
                                    label: 'Watching',
                                    icon: Icons.play_arrow_rounded,
                                  ),
                                  AppSegmentedControlItem(
                                    value: 'PLANNING',
                                    label: 'Planning',
                                    icon: Icons.calendar_today_outlined,
                                  ),
                                  AppSegmentedControlItem(
                                    value: 'COMPLETED',
                                    label: 'Watched',
                                    icon: Icons.check_circle_outline_rounded,
                                  ),
                                ],
                                groupValue: _controller.activeStatus,
                                onValueChanged: _controller.switchTab,
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