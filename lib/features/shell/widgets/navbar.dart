import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../data/anilist/models/anime.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/hover_focus_builder.dart';
import 'search_input.dart';

class AniStreamNavBar extends StatefulWidget implements PreferredSizeWidget {
  final String searchQuery;
  final bool isLoggedIn;
  final bool isScrolled;
  final bool uiPerformanceMode;

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
    this.uiPerformanceMode = false,
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
  bool _mobileSearchActive = false;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

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
    _isMaximised
        ? await windowManager.unmaximize()
        : await windowManager.maximize();
  }

  void _closeMobileSearch() {
    setState(() => _mobileSearchActive = false);
    _searchController.clear();
    widget.onSearch?.call('');
    FocusScope.of(context).unfocus();
  }

  void _showMobileMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Menu',
      barrierColor: AppPalette.black.withValues(alpha: 0.50),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
      pageBuilder: (_, _, _) => _MobileMenu(
        isLoggedIn: widget.isLoggedIn,
        uiPerformanceMode: widget.uiPerformanceMode,
        onScheduled: widget.onScheduled,
        onWatchlist: widget.onWatchlist,
        onLogin: widget.onLogin,
        onSettings: widget.onSettings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: widget.isScrolled ? 16.0 : 0.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, blurAmount, child) {
        Widget navContent = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: widget.preferredSize.height,
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24),
          decoration: BoxDecoration(
            color: widget.isScrolled
                // ── Increase opacity from 0.75 to 0.95 if blur is removed ──
                ? AppPalette.base.withValues(
                    alpha: widget.uiPerformanceMode ? 0.95 : 0.75,
                  )
                : AppPalette.transparent,
            border: Border(
              bottom: BorderSide(
                color: AppPalette.white.withValues(
                  alpha: widget.isScrolled ? 0.05 : 0.0,
                ),
                width: 1,
              ),
            ),
          ),
          child: child,
        );

        // ── Conditional Blur ──
        if (!widget.uiPerformanceMode) {
          navContent = BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
            child: navContent,
          );
        }

        return ClipRRect(child: navContent);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: isCompact && _mobileSearchActive
            ? _buildMobileSearchMode()
            : _buildStandardLayout(isCompact),
      ),
    );
  }

  Widget _buildMobileSearchMode() {
    return Row(
      key: const ValueKey('mobile_search'),
      children: [
        IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppPalette.textMain,
            size: 20,
          ),
          onPressed: _closeMobileSearch,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SearchInput(
            controller: _searchController,
            autoFocus: true,
            uiPerformanceMode: widget.uiPerformanceMode,
            onChanged: widget.onSearch,
            onSubmitted: (query) {
              setState(() => _mobileSearchActive = false);
              widget.onSubmitted?.call(query);
            },
            onSelectAnime: (anime) {
              setState(() => _mobileSearchActive = false);
              widget.onSelectAnime?.call(anime);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStandardLayout(bool isCompact) {
    return Row(
      key: const ValueKey('standard_nav'),
      children: [
        _NavLogo(onTap: widget.onHome),
        if (!isCompact) const SizedBox(width: 32),
        if (!isCompact)
          Expanded(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SearchInput(
                controller: _searchController,
                uiPerformanceMode: widget.uiPerformanceMode,
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
        if (isCompact)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavIconButton(
                icon: Icons.search_rounded,
                tooltip: 'Search',
                onPressed: () => setState(() => _mobileSearchActive = true),
              ),
              _NavIconButton(
                icon: Icons.menu_rounded,
                tooltip: 'Menu',
                onPressed: _showMobileMenu,
              ),
            ],
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavIconButton(
                icon: Icons.calendar_month_outlined,
                tooltip: 'Schedule',
                onPressed: widget.onScheduled,
              ),
              if (widget.isLoggedIn) ...[
                const SizedBox(width: 2),
                _NavIconButton(
                  icon: Icons.video_library_outlined,
                  tooltip: 'My Watchlist',
                  onPressed: widget.onWatchlist,
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  width: 1,
                  height: 18,
                  color: AppPalette.white.withValues(alpha: 0.1),
                ),
              ),
              _UserButton(
                isLoggedIn: widget.isLoggedIn,
                onPressed: widget.onLogin,
              ),
              const SizedBox(width: 2),
              _NavIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onPressed: widget.onSettings,
              ),
            ],
          ),
        if (_isDesktop) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              width: 1,
              height: 18,
              color: AppPalette.white.withValues(alpha: 0.1),
            ),
          ),
          _WindowButton(
            icon: Icons.remove_rounded,
            tooltip: 'Minimise',
            onPressed: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: _isMaximised
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            tooltip: _isMaximised ? 'Restore' : 'Maximise',
            hoverColor: AppPalette.accent,
            onPressed: _handleMaximise,
          ),
          _WindowButton(
            icon: Icons.close_rounded,
            tooltip: 'Quit',
            hoverColor: AppPalette.statusCancelled,
            onPressed: () => windowManager.close(),
          ),
        ],
      ],
    );
  }
}

class _MobileMenu extends StatelessWidget {
  final bool isLoggedIn;
  final bool uiPerformanceMode; // ── NEW ──
  final VoidCallback? onScheduled;
  final VoidCallback? onWatchlist;
  final VoidCallback? onLogin;
  final VoidCallback? onSettings;

  const _MobileMenu({
    required this.isLoggedIn,
    this.uiPerformanceMode = false,
    this.onScheduled,
    this.onWatchlist,
    this.onLogin,
    this.onSettings,
  });

  void _handleTap(BuildContext context, VoidCallback? action) {
    Navigator.of(context).pop();
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    Widget menuContent = Container(
      decoration: BoxDecoration(
        color: AppPalette.base.withValues(
          alpha: uiPerformanceMode ? 0.95 : 0.65,
        ),
        border: Border(
          left: BorderSide(
            color: AppPalette.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Menu',
                    style: TextStyle(
                      color: AppPalette.textMain,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppPalette.textMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _MobileMenuTile(
              icon: Icons.calendar_month_outlined,
              title: 'Schedule',
              onTap: () => _handleTap(context, onScheduled),
            ),
            if (isLoggedIn)
              _MobileMenuTile(
                icon: Icons.video_library_outlined,
                title: 'My Watchlist',
                onTap: () => _handleTap(context, onWatchlist),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Divider(color: AppPalette.white.withValues(alpha: 0.1)),
            ),
            _MobileMenuTile(
              icon: Icons.person_outline_rounded,
              title: isLoggedIn ? 'Log out of AniList' : 'Log in to AniList',
              iconColor: isLoggedIn
                  ? AppPalette.statusCancelled
                  : AppPalette.statusReleasing,
              onTap: () => _handleTap(context, onLogin),
            ),
            _MobileMenuTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () => _handleTap(context, onSettings),
            ),
          ],
        ),
      ),
    );

    // ── Conditional Blur ──
    if (!uiPerformanceMode) {
      menuContent = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: menuContent,
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.85,
          height: double.infinity,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomLeft: Radius.circular(24),
            ),
            child: menuContent,
          ),
        ),
      ),
    );
  }
}

class _MobileMenuTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color? iconColor;
  final VoidCallback onTap;

  const _MobileMenuTile({
    required this.icon,
    required this.title,
    this.iconColor,
    required this.onTap,
  });

  @override
  State<_MobileMenuTile> createState() => _MobileMenuTileState();
}

class _MobileMenuTileState extends State<_MobileMenuTile> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) => setState(() => _isDown = false),
      onTapCancel: () => setState(() => _isDown = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _isDown
            ? AppPalette.white.withValues(alpha: 0.1)
            : AppPalette.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 24,
              color: widget.iconColor ?? AppPalette.textMuted,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppPalette.border,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavLogo extends StatelessWidget {
  final VoidCallback? onTap;
  const _NavLogo({this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      onTap: onTap,
      builder: (context, hovered) => AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 150),
        style: TextStyle(
          color: hovered ? AppPalette.primary : AppPalette.textMain,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('AniStream'),
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      tooltip: tooltip,
      onTap: onPressed,
      builder: (context, hovered) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 22,
          color: hovered ? AppPalette.primary : AppPalette.textMuted,
        ),
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
    return HoverFocusBuilder(
      tooltip: isLoggedIn ? 'Log out of AniList' : 'Log in to AniList',
      onTap: onPressed,
      builder: (context, hovered) {
        Color iconColor;
        if (isLoggedIn) {
          iconColor = hovered
              ? AppPalette.statusCancelled
              : AppPalette.statusReleasing;
        } else {
          iconColor = hovered ? AppPalette.textMain : AppPalette.textMuted;
        }
        return Container(
          width: 44,
          height: 44,
          color: AppPalette.transparent,
          alignment: Alignment.center,
          child: Icon(Icons.person_outline_rounded, color: iconColor, size: 22),
        );
      },
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? hoverColor;
  final VoidCallback? onPressed;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    this.hoverColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      tooltip: tooltip,
      onTap: onPressed,
      builder: (context, hovered) => Container(
        width: 44,
        height: 44,
        color: AppPalette.transparent,
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: hovered
              ? (hoverColor ?? AppPalette.textMain)
              : AppPalette.textMuted,
          size: 20,
        ),
      ),
    );
  }
}
