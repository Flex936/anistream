// Displays the authenticated user's CURRENT ("Watching") and PLANNING lists
// fetched from AniList via [AnilistApiService.getUserWatchlist].
// Tapping a card calls [onSelectAnime], routing through AppShell so the
// NavBar stays visible — identical to HomeScreen and SearchResultsScreen.

import 'dart:ui';
import 'package:flutter/material.dart';

import '../services/anilist_query_service.dart';
import '../theme/app_palette.dart';

// ════════════════════════════════════════════════════════════════════════════
//  File-private helpers
// ════════════════════════════════════════════════════════════════════════════

// ── FIXED: Status coloring utility injected locally ──
Color _statusColor(String? s) => switch (s) {
      'RELEASING' => AppPalette.statusReleasing,
      'FINISHED' => AppPalette.statusFinished,
      'CANCELLED' => AppPalette.statusCancelled,
      'HIATUS' => AppPalette.statusHiatus,
      _ => AppPalette.statusDefault,
    };

// ════════════════════════════════════════════════════════════════════════════
//  WatchlistScreen
// ════════════════════════════════════════════════════════════════════════════

class WatchlistScreen extends StatefulWidget {
  final ValueChanged<Anime>? onSelectAnime;

  const WatchlistScreen({super.key, this.onSelectAnime});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _api = AnilistQueryService();

  bool _loading = true;
  String? _error;
  List<MediaList> _lists = [];
  String _activeStatus = 'CURRENT'; // 'CURRENT' | 'PLANNING' | 'COMPLETED'
  
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

  String _getEmptyMessage() {
    if (_activeStatus == 'CURRENT') return "You're not watching anything yet.";
    if (_activeStatus == 'PLANNING') return "Your planning list is empty.";
    return "You haven't completed any anime yet.";
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Dynamic Background Layer
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
                        errorBuilder: (context, error, stackTrace) {
                          return const ColoredBox(color: AppPalette.base);
                        },
                      ),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                        child: Container(color: AppPalette.base.withValues(alpha: 0.85)),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ),

        // 2. The scrollable content
        Positioned.fill(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 96),

                // ── Header + tabs + toggles ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 32, 
                    runSpacing: 16,
                    children: [
                      const Text(
                        'My Library',
                        style: TextStyle(color: AppPalette.textMain, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4),
                      ),
                      
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Grid vs List Toggle
                            Container(
                              decoration: BoxDecoration(
                                color: AppPalette.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppPalette.border),
                              ),
                              child: Row(
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
                            const SizedBox(width: 16),
                            // Watching / Planning / Watched Tabs
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppPalette.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppPalette.border),
                              ),
                              child: Row(
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
                      ),
                    ],
                  ),
                ),

                // ── Body ──
                if (_loading)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: const _LoadingPane())
                else if (_error != null)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: _ErrorPane(message: _error!, onRetry: _fetchWatchlist))
                else if (_activeEntries.isEmpty)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: _EmptyPane(message: _getEmptyMessage()))
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
        // Both PLANNING and COMPLETED will use the vertical poster layout
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
              return _HeroCard(
                entry: entry,
                onTap: () => widget.onSelectAnime?.call(entry.media),
                onHover: (hovered) => _handleHover(hoverImage, hovered),
              );
            } else {
              return _WatchlistCard(
                entry: entry,
                // Only show progress logic for Currently Watching items
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
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, i) => _ListCard(
        entry: _activeEntries[i],
        showProgress: _activeStatus == 'CURRENT',
        onTap: () => widget.onSelectAnime?.call(_activeEntries[i].media),
        onHover: (hovered) => _handleHover(_activeEntries[i].media.bannerImage ?? _activeEntries[i].media.coverImage?.display, hovered),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _HeroCard (16:9 Continue Watching Card)
// ════════════════════════════════════════════════════════════════════════════

class _HeroCard extends StatefulWidget {
  final MediaListEntry entry;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _HeroCard({required this.entry, required this.onTap, required this.onHover});

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.entry.media;
    final progress = widget.entry.progress;
    final imgUrl = media.bannerImage ?? media.coverImage?.display;
    
    double percent = 0.0;
    if (media.episodes != null && media.episodes! > 0) {
      percent = progress / media.episodes!;
    } else if (progress > 0) {
      percent = 0.1;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) { setState(() => _hovered = true); widget.onHover(true); },
      onExit: (_) { setState(() => _hovered = false); widget.onHover(false); },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _hovered ? AppPalette.primary.withValues(alpha: 0.5) : AppPalette.border),
            boxShadow: _hovered ? [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.2), blurRadius: 20)] : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _PosterImage(url: imgUrl, hovered: _hovered),
                
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, AppPalette.black.withValues(alpha: 0.9)],
                    ),
                  ),
                ),

                Center(
                  child: AnimatedScale(
                    scale: _hovered ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: AppPalette.white, size: 32),
                    ),
                  ),
                ),

                Positioned(
                  bottom: 16, left: 16, right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(media.title.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppPalette.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Continue Episode ${progress + 1}', style: const TextStyle(color: AppPalette.textLight, fontSize: 12)),
                    ],
                  ),
                ),

                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 3,
                    alignment: Alignment.centerLeft,
                    color: AppPalette.black,
                    child: FractionallySizedBox(
                      widthFactor: percent.clamp(0.0, 1.0),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppPalette.primary,
                          boxShadow: [BoxShadow(color: AppPalette.primary, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _ListCard (Dense layout for Planning/Watched list)
// ════════════════════════════════════════════════════════════════════════════

class _ListCard extends StatefulWidget {
  final MediaListEntry entry;
  final bool showProgress;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _ListCard({required this.entry, required this.showProgress, required this.onTap, required this.onHover});

  @override
  State<_ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<_ListCard> {
  bool _hovered = false;

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return 'No synopsis available.';
    return html.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.entry.media;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) { setState(() => _hovered = true); widget.onHover(true); },
      onExit: (_) { setState(() => _hovered = false); widget.onHover(false); },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered ? AppPalette.surface.withValues(alpha: 0.8) : AppPalette.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _hovered ? AppPalette.primary.withValues(alpha: 0.5) : AppPalette.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 0.7,
                  child: _PosterImage(url: media.coverImage?.display, hovered: _hovered),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.title.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppPalette.textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    
                    // ── FIXED: Added back Text.rich for distinct status & score colors ──
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: (media.status ?? 'UNKNOWN').replaceAll('_', ' '),
                            style: TextStyle(
                              color: _statusColor(media.status),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const TextSpan(
                            text: '  •  ',
                            style: TextStyle(color: AppPalette.textMuted, fontSize: 12),
                          ),
                          TextSpan(
                            text: '★ ${(media.averageScore ?? 0) / 10}',
                            style: const TextStyle(
                              color: AppPalette.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          TextSpan(
                            text: '  •  ${media.episodes ?? "?"} EPS',
                            style: const TextStyle(color: AppPalette.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!isMobile && media.genres != null && media.genres!.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        children: media.genres!.take(4).map((g) => Text('#$g', style: const TextStyle(color: AppPalette.primary, fontSize: 11))).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: Text(
                        _stripHtml(media.description),
                        maxLines: isMobile ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppPalette.textMuted, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _WatchlistCard (Upgraded Grid Layout for Planning/Watched Tab)
// ════════════════════════════════════════════════════════════════════════════

class _WatchlistCard extends StatefulWidget {
  final MediaListEntry entry;
  final bool showProgress;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _WatchlistCard({required this.entry, required this.showProgress, required this.onTap, required this.onHover});

  @override
  State<_WatchlistCard> createState() => _WatchlistCardState();
}

class _WatchlistCardState extends State<_WatchlistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final media = widget.entry.media;
    final progress = widget.entry.progress;
    final nextEp = media.nextAiringEpisode;

    double percent = 0.0;
    if (media.episodes != null && media.episodes! > 0) {
      percent = progress / media.episodes!;
    } else if (progress > 0) {
      percent = 0.1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) { setState(() => _hovered = true); widget.onHover(true); },
            onExit: (_) { setState(() => _hovered = false); widget.onHover(false); },
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _hovered ? AppPalette.primary.withValues(alpha: 0.55) : AppPalette.border),
                  boxShadow: _hovered ? [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.18), blurRadius: 24)] : [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _PosterImage(url: media.coverImage?.display, hovered: _hovered),

                      if (widget.showProgress)
                        Positioned(
                          top: 8, right: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppPalette.black.withValues(alpha: 0.6),
                                  border: Border.all(color: AppPalette.white.withValues(alpha: 0.15)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.play_arrow_rounded, color: AppPalette.primary, size: 12),
                                    const SizedBox(width: 4),
                                    Text('EP $progress / ${media.episodes ?? "?"}', style: const TextStyle(color: AppPalette.textMain, fontSize: 10, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      _PlayOverlay(visible: _hovered, episode: progress + 1),

                      if (widget.showProgress)
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            height: 3,
                            alignment: Alignment.centerLeft,
                            color: AppPalette.black,
                            child: FractionallySizedBox(
                              widthFactor: percent.clamp(0.0, 1.0),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppPalette.primary,
                                  boxShadow: [BoxShadow(color: AppPalette.primary, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(color: _hovered ? AppPalette.primary : AppPalette.textMain, fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
          child: Text(media.title.display, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: 4),
        if (nextEp != null && nextEp.episode > 0)
          Text('Ep ${nextEp.episode} airing soon', style: const TextStyle(color: AppPalette.primary, fontSize: 11, fontWeight: FontWeight.w600))
        else
          Text('${media.episodes ?? "?"} episodes', style: const TextStyle(color: AppPalette.textMuted, fontSize: 11)),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _TabButton 
// ════════════════════════════════════════════════════════════════════════════

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppPalette.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active ? [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? Colors.white : AppPalette.textMuted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? Colors.white : AppPalette.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _PosterImage 
// ════════════════════════════════════════════════════════════════════════════

class _PosterImage extends StatelessWidget {
  final String? url;
  final bool hovered;

  const _PosterImage({this.url, required this.hovered});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(color: AppPalette.surface, child: Center(child: Icon(Icons.image_not_supported_outlined, color: AppPalette.textMuted, size: 36)));
    }

    return AnimatedScale(
      scale: hovered ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppPalette.surface),
              AnimatedOpacity(opacity: frame != null ? 1.0 : 0.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut, child: child),
            ],
          );
        },
        errorBuilder: (_, _, _) => const ColoredBox(color: AppPalette.surface, child: Center(child: Icon(Icons.broken_image_outlined, color: AppPalette.textMuted, size: 36))),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _PlayOverlay
// ════════════════════════════════════════════════════════════════════════════

class _PlayOverlay extends StatelessWidget {
  final bool visible;
  final int episode;

  const _PlayOverlay({required this.visible, required this.episode});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.52),
          child: Center(
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.12),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(color: AppPalette.primary, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: AppPalette.primary.withValues(alpha: 0.55), blurRadius: 18)]),
                child: Text('Play EP $episode', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  State panes 
// ════════════════════════════════════════════════════════════════════════════

class _LoadingPane extends StatelessWidget {
  const _LoadingPane();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppPalette.primary), strokeWidth: 2.5));
}

class _EmptyPane extends StatelessWidget {
  final String message;
  const _EmptyPane({required this.message});

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
            const Icon(Icons.video_library_outlined, color: AppPalette.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: AppPalette.textMuted, fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            const Text('Find something new to watch!', style: TextStyle(color: AppPalette.textMuted, fontSize: 13)),
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