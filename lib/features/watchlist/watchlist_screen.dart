import 'dart:ui';
import 'package:flutter/material.dart';

import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/media_list.dart';
import '../../data/anilist/models/anime.dart';
import '../../core/theme/app_palette.dart';
import 'widgets/watchlist_cards.dart';

class WatchlistScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const WatchlistScreen({super.key, this.onSelectAnime});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final AnilistQueryService _api = AnilistQueryService();

  bool _loading = true;
  String? _error;
  List<MediaList> _lists = [];
  String _activeStatus = 'CURRENT'; 
  
  bool _isListView = false;
  String? _hoveredBanner;

  @override
  void initState() {
    super.initState();
    _fetchWatchlist();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchWatchlist() async {
    setState(() { _loading = true; _error = null; });
    try {
      final lists = await _api.getUserWatchlist();
      if (mounted) setState(() { _lists = lists; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<MediaListEntry> get _activeEntries => _lists
      .where((l) => l.status == _activeStatus)
      .expand((l) => l.entries)
      .toList();

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
                        errorBuilder: (context, error, stackTrace) => const ColoredBox(color: AppPalette.base),
                      ),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                        child: Container(color: AppPalette.base.withValues(alpha: 0.85)),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),

        Positioned.fill(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 96),

                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 32, 
                    runSpacing: 16,
                    children: [
                      const Text('My Library', style: TextStyle(color: AppPalette.textMain, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
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
                                  icon: Icon(Icons.grid_view_rounded, size: 20, color: !_isListView ? AppPalette.primary : AppPalette.textMuted),
                                  onPressed: () => setState(() => _isListView = false),
                                ),
                                IconButton(
                                  icon: Icon(Icons.view_list_rounded, size: 20, color: _isListView ? AppPalette.primary : AppPalette.textMuted),
                                  onPressed: () => setState(() => _isListView = true),
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
                                  icon: Icons.play_arrow_rounded, label: 'Watching',
                                  active: _activeStatus == 'CURRENT',
                                  onTap: () => setState(() => _activeStatus = 'CURRENT'),
                                ),
                                _TabButton(
                                  icon: Icons.calendar_today_outlined, label: 'Planning',
                                  active: _activeStatus == 'PLANNING',
                                  onTap: () => setState(() => _activeStatus = 'PLANNING'),
                                ),
                                _TabButton(
                                  icon: Icons.check_circle_outline_rounded, label: 'Watched',
                                  active: _activeStatus == 'COMPLETED',
                                  onTap: () => setState(() => _activeStatus = 'COMPLETED'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (_loading)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: const _LoadingPane())
                else if (_error != null)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: _ErrorPane(message: _error!, onRetry: _fetchWatchlist))
                else if (_activeEntries.isEmpty)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: _buildEmptyState())
                else
                  _isListView ? _buildListLayout() : _buildGridLayout(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridLayout() {
    final isWatching = _activeStatus == 'CURRENT';

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = isWatching ? _landscapeColumns(constraints.maxWidth) : _verticalColumns(constraints.maxWidth);
        final aspectRatio = isWatching ? 1.77 : 0.52;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 20,
            mainAxisSpacing: 24,
            childAspectRatio: aspectRatio,
          ),
          itemCount: _activeEntries.length,
          itemBuilder: (_, i) {
            final entry = _activeEntries[i];
            final hoverImage = entry.media.bannerImage ?? entry.media.coverImage?.display;

            if (isWatching) {
              return HeroCard(
                entry: entry,
                onTap: () => widget.onSelectAnime?.call(entry.media),
                onHover: (hovered) => _handleHover(hoverImage, hovered),
              );
            } else {
              return WatchlistCard(
                entry: entry,
                listStatus: _activeStatus,
                showProgress: false, 
                onTap: () => widget.onSelectAnime?.call(entry.media),
                onHover: (hovered) => _handleHover(hoverImage, hovered),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildListLayout() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
      itemCount: _activeEntries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, i) => ListCard(
        entry: _activeEntries[i],
        showProgress: _activeStatus == 'CURRENT',
        onTap: () => widget.onSelectAnime?.call(_activeEntries[i].media),
        onHover: (hovered) => _handleHover(_activeEntries[i].media.bannerImage ?? _activeEntries[i].media.coverImage?.display, hovered),
      ),
    );
  }
}

// ── Private sub-widgets for Screen ──

// ── FIXED: Converted to StatefulWidget for rich hover interactions ──
class _TabButton extends StatefulWidget {
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
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.active
        ? AppPalette.primary
        : (_hovered ? AppPalette.white.withValues(alpha: 0.08) : AppPalette.transparent);

    final contentColor = widget.active
        ? AppPalette.white
        : (_hovered ? AppPalette.textMain : AppPalette.textMuted);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.active
                ? [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: contentColor),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: contentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary), strokeWidth: 2.5));
}

class _EmptyPane extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyPane({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(32, 0, 32, 32),
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppPalette.border, style: BorderStyle.solid)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppPalette.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: AppPalette.textMain, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: AppPalette.textMuted, fontSize: 13)),
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
          const Icon(Icons.wifi_off_rounded, color: AppPalette.textMuted, size: 52),
          const SizedBox(height: 16),
          const Text('Could not load watchlist', style: TextStyle(color: AppPalette.textMain, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.textMuted, fontSize: 13)),
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