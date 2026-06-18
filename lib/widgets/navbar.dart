import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/anilist_query_service.dart';
import '../../theme/app_palette.dart';
import './navbar/nav_action_buttons.dart';
import './navbar/nav_logo.dart';
import './navbar/search_input.dart';

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
    if (old.searchQuery != widget.searchQuery &&
        _searchController.text != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncMaximisedState() async {
    if (!_isDesktop) return;
    final max = await windowManager.isMaximized();
    if (mounted && max != _isMaximised) {
      setState(() => _isMaximised = max);
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximised = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximised = false);

  Future<void> _handleMaximise() async {
    if (!_isDesktop) return;
    if (_isMaximised) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600; 

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
                color: widget.isScrolled
                    ? AppPalette.base.withValues(alpha: 0.75) 
                    : AppPalette.transparent,
              ),
              child: child,
            ),
          ),
        );
      },
      child: Row(
        children: [
          if (!isCompact) ...[
            NavLogo(onTap: widget.onHome),
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
            const Expanded(
              child: DragToMoveArea(child: SizedBox(height: double.infinity)),
            )
          else 
            const Spacer(), 

          NavIconButton(
            icon: Icons.calendar_month_outlined,
            tooltip: 'Schedule',
            onPressed: widget.onScheduled,
          ),
          if (widget.isLoggedIn) ...[
            const SizedBox(width: 2),
            NavIconButton(
              icon: Icons.video_library_outlined,
              tooltip: 'My Watchlist',
              onPressed: widget.onWatchlist,
            ),
          ],
          const SizedBox(width: 2),
          UserButton(isLoggedIn: widget.isLoggedIn, onPressed: widget.onLogin),
          const SizedBox(width: 2),
          NavIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: widget.onSettings,
          ),

          if (_isDesktop) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(width: 1, height: 20, color: AppPalette.border.withValues(alpha: widget.isScrolled ? 1.0 : 0.0)),
            ),
            WindowButton(icon: Icons.remove_rounded, tooltip: 'Minimise', onPressed: () => windowManager.minimize()),
            WindowButton(
              icon: _isMaximised ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              tooltip: _isMaximised ? 'Restore' : 'Maximise',
              hoverColor: AppPalette.accent,
              onPressed: _handleMaximise,
            ),
            WindowButton(icon: Icons.close_rounded, tooltip: 'Quit', hoverColor: AppPalette.statusCancelled, onPressed: () => windowManager.close()),
          ],
        ],
      ),
    );
  }
}