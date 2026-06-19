import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../data/anilist/models/anime.dart';
import '../../../core/theme/app_palette.dart';
import 'search_input.dart';

class AniStreamNavBar extends StatefulWidget implements PreferredSizeWidget {
  final String searchQuery;
  final bool isLoggedIn;
  final bool isScrolled; 
  
  final ValueChanged<String>? onSearch;
  final VoidCallback? onHome;
  final VoidCallback? onLogin;
  final VoidCallback? onSettings;
  final VoidCallback? onWatchlist;
  final VoidCallback? onScheduled;
  final ValueChanged<Anime>? onSelectAnime;
  final ValueChanged<String>? onSubmitted;

  const AniStreamNavBar({
    super.key,
    this.searchQuery = '',
    this.isLoggedIn = false,
    this.isScrolled = false,
    this.onSearch,
    this.onHome,
    this.onLogin,
    this.onSettings,
    this.onWatchlist,
    this.onScheduled,
    this.onSelectAnime,
    this.onSubmitted,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  State<AniStreamNavBar> createState() => _AniStreamNavBarState();
}

class _AniStreamNavBarState extends State<AniStreamNavBar> with WindowListener {
  late final TextEditingController _searchController;
  bool _isMaximised = true; 

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
    
    if (_isDesktop) {
      windowManager.addListener(this);
      _syncMaximisedState();
    }
  }

  @override
  void didUpdateWidget(AniStreamNavBar old) {
    super.didUpdateWidget(old);
    if (old.searchQuery != widget.searchQuery && _searchController.text != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximisedState() async {
    if (!_isDesktop) return;
    final max = await windowManager.isMaximized();
    if (mounted && max != _isMaximised) setState(() => _isMaximised = max);
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximised = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximised = false);

  Future<void> _handleMaximise() async {
    if (!_isDesktop) return;
    _isMaximised ? await windowManager.unmaximize() : await windowManager.maximize();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 600; 

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: widget.isScrolled ? 16.0 : 0.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, blurAmount, child) {
        return ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: widget.preferredSize.height,
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24),
              decoration: BoxDecoration(
                color: widget.isScrolled ? AppPalette.base.withValues(alpha: 0.75) : AppPalette.transparent,
              ),
              child: child,
            ),
          ),
        );
      },
      child: Row(
        children: [
          if (!isCompact) ...[
            _NavLogo(onTap: widget.onHome),
            const SizedBox(width: 32),
          ],

          Expanded(
            flex: isCompact ? 1 : 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SearchInput(
                controller: _searchController,
                onChanged: widget.onSearch,
                onSubmitted: widget.onSubmitted,
                onSelectAnime: widget.onSelectAnime,
              ),
            ),
          ),

          if (_isDesktop)
            const Expanded(child: DragToMoveArea(child: SizedBox(height: double.infinity)))
          else 
            const Spacer(), 

          _NavIconButton(icon: Icons.calendar_month_outlined, tooltip: 'Schedule', onPressed: widget.onScheduled),
          if (widget.isLoggedIn) ...[
            const SizedBox(width: 2),
            _NavIconButton(icon: Icons.video_library_outlined, tooltip: 'My Watchlist', onPressed: widget.onWatchlist),
          ],
          const SizedBox(width: 2),
          _UserButton(isLoggedIn: widget.isLoggedIn, onPressed: widget.onLogin),
          const SizedBox(width: 2),
          _NavIconButton(icon: Icons.settings_outlined, tooltip: 'Settings', onPressed: widget.onSettings),

          if (_isDesktop) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(width: 1, height: 20, color: AppPalette.border.withValues(alpha: widget.isScrolled ? 1.0 : 0.0)),
            ),
            _WindowButton(icon: Icons.remove_rounded, tooltip: 'Minimise', onPressed: () => windowManager.minimize()),
            _WindowButton(
              icon: _isMaximised ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              tooltip: _isMaximised ? 'Restore' : 'Maximise',
              hoverColor: AppPalette.accent,
              onPressed: _handleMaximise,
            ),
            _WindowButton(icon: Icons.close_rounded, tooltip: 'Quit', hoverColor: AppPalette.statusCancelled, onPressed: () => windowManager.close()),
          ],
        ],
      ),
    );
  }
}

// ── Private Stateless Components ─────────────────────────────────────────────

class _NavLogo extends StatelessWidget {
  final VoidCallback? onTap;
  const _NavLogo({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: AppPalette.white.withValues(alpha: 0.1),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'AniStream',
          style: TextStyle(color: AppPalette.textMain, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NavIconButton({required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: IconButton(
        icon: Icon(icon),
        iconSize: 22,
        color: AppPalette.textMuted,
        hoverColor: AppPalette.white.withValues(alpha: 0.1),
        splashColor: AppPalette.primary.withValues(alpha: 0.2),
        highlightColor: AppPalette.primary.withValues(alpha: 0.1),
        onPressed: onPressed,
      ),
    );
  }
}

class _UserButton extends StatelessWidget {
  final bool isLoggedIn;
  final VoidCallback? onPressed;

  const _UserButton({required this.isLoggedIn, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isLoggedIn ? 'Log out of AniList' : 'Log in to AniList',
      waitDuration: const Duration(milliseconds: 600),
      child: IconButton(
        icon: const Icon(Icons.person_outline_rounded),
        iconSize: 22,
        color: isLoggedIn ? AppPalette.statusReleasing : AppPalette.textMuted,
        hoverColor: AppPalette.white.withValues(alpha: 0.1),
        splashColor: AppPalette.primary.withValues(alpha: 0.2),
        onPressed: onPressed,
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? hoverColor;
  final VoidCallback? onPressed;

  const _WindowButton({required this.icon, required this.tooltip, this.hoverColor, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: IconButton(
        icon: Icon(icon),
        iconSize: 20,
        color: AppPalette.textMuted,
        hoverColor: (hoverColor ?? AppPalette.textMain).withValues(alpha: 0.15),
        onPressed: onPressed,
      ),
    );
  }
}