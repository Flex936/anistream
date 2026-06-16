import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_palette.dart';
import 'navbar/nav_action_buttons.dart';
import 'navbar/nav_logo.dart';
import 'navbar/search_input.dart';

class AniStreamNavBar extends StatefulWidget implements PreferredSizeWidget {
  final String searchQuery;
  final bool isLoggedIn;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onHome;
  final VoidCallback? onLogin;
  final VoidCallback? onSettings;
  final VoidCallback? onWatchlist;
  final VoidCallback? onScheduled;

  const AniStreamNavBar({
    super.key,
    this.searchQuery = '',
    this.isLoggedIn = false,
    this.onSearch,
    this.onHome,
    this.onLogin,
    this.onSettings,
    this.onWatchlist,
    this.onScheduled,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  State<AniStreamNavBar> createState() => _AniStreamNavBarState();
}

class _AniStreamNavBarState extends State<AniStreamNavBar> with WindowListener {
  late final TextEditingController _searchController;
  bool _isMaximised = true; // Assume true if launching maximized from main.dart

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
    windowManager.addListener(this);
    _syncMaximisedState();
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
    windowManager.removeListener(this);
    super.dispose();
  }

  // Syncs state without causing a UI stutter
  Future<void> _syncMaximisedState() async {
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
    if (_isMaximised) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.preferredSize.height,
      decoration: const BoxDecoration(
        color: AppPalette.base,
        border: Border(bottom: BorderSide(color: AppPalette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // ── Logo ─────────────────────────────────────────────────────────
          NavLogo(onTap: widget.onHome),
          const SizedBox(width: 32),

          // ── Search ───────────────────────────────────────────────────────
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, minWidth: 200),
            child: SearchInput(
              controller: _searchController,
              onChanged: widget.onSearch,
            ),
          ),

          // ── THE OPTIMIZATION: Dedicated Drag Zone ────────────────────────
          // This Expanded widget pushes all the buttons to the right and acts
          // as the ONLY draggable area. This completely eliminates the
          // hit-testing lag caused by wrapping the entire Row!
          const Expanded(
            child: DragToMoveArea(child: SizedBox(height: double.infinity)),
          ),

          // ── Right-side actions ───────────────────────────────────────────
          NavIconButton(
            icon: Icons.calendar_month_outlined,
            tooltip: 'Schedule',
            onPressed: widget.onScheduled,
          ),
          if (widget.isLoggedIn) ...[
            const SizedBox(width: 4),
            NavIconButton(
              icon: Icons.video_library_outlined,
              tooltip: 'My Watchlist',
              onPressed: widget.onWatchlist,
            ),
          ],
          const SizedBox(width: 4),
          UserButton(isLoggedIn: widget.isLoggedIn, onPressed: widget.onLogin),
          const SizedBox(width: 4),
          NavIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: widget.onSettings,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(width: 1, height: 20, color: AppPalette.border),
          ),

          WindowButton(
            icon: Icons.remove_rounded,
            tooltip: 'Minimise',
            onPressed: () => windowManager.minimize(),
          ),
          WindowButton(
            icon: _isMaximised
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            tooltip: _isMaximised ? 'Restore' : 'Maximise',
            hoverColor: AppPalette.accent,
            onPressed: _handleMaximise,
          ),
          WindowButton(
            icon: Icons.close_rounded,
            tooltip: 'Quit',
            hoverColor: AppPalette.statusCancelled,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}
