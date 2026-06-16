// lib/widgets/navbar.dart
//
// Application navigation bar for AniStream.
// Translates NavBar.svelte into Flutter.
//
// Implements [PreferredSizeWidget] so it slots directly into [Scaffold.appBar].
// [DragToMoveArea] from window_manager makes blank bar areas draggable for
// moving the window — mirroring the `--wails-draggable: drag` CSS property on
// the <nav> element. Interactive children (buttons, TextField) absorb their own
// gestures before the pan recogniser fires, so clicks always register correctly.
//
// Required pubspec dependency:
//   window_manager: ^0.3.8

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_palette.dart'; // AppPalette

// ════════════════════════════════════════════════════════════════════════════
//  AniStreamNavBar
// ════════════════════════════════════════════════════════════════════════════

/// Top navigation bar — equivalent to NavBar.svelte.
///
/// Usage in an app-shell [Scaffold]:
/// ```dart
/// Scaffold(
///   appBar: AniStreamNavBar(
///     isLoggedIn: _isLoggedIn,
///     onHome:      () => _navigate(const HomeScreen()),
///     onSearch:    (q) => _navigate(SearchScreen(query: q)),
///     onScheduled: () => _navigate(const ScheduleScreen()),
///     onWatchlist: () => _navigate(const WatchlistScreen()),
///     onLogin:     _handleLogin,
///     onSettings:  () => showSettingsMenu(context),
///   ),
///   body: _currentScreen,
/// )
/// ```
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

  /// py-4 (16 px) top + 16 px bottom + ~40 px for icon/input content = 72 px.
  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  State<AniStreamNavBar> createState() => _AniStreamNavBarState();
}

class _AniStreamNavBarState extends State<AniStreamNavBar> with WindowListener {
  late final TextEditingController _searchController;
  bool _isMaximised = false;

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
    // Keep the controller in sync when the parent clears or sets the query
    // externally (e.g. navigating back to Home resets the search field).
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

  Future<void> _syncMaximisedState() async {
    final max = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximised = max);
  }

  // ── WindowListener callbacks ─────────────────────────────────────────────

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
    // DragToMoveArea covers the full bar so the window can be dragged from
    // any blank region, matching `--wails-draggable: drag` on <nav>.
    return DragToMoveArea(
      child: Container(
        height: widget.preferredSize.height,
        decoration: const BoxDecoration(
          color: AppPalette.base,
          border: Border(bottom: BorderSide(color: AppPalette.border)),
        ),
        // px-6 matches NavBar.svelte. Vertical centering is handled by the Row.
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            // ── Logo ─────────────────────────────────────────────────────────
            _NavLogo(onTap: widget.onHome),
            const SizedBox(width: 32),

            // ── Search (flex-1 max-w-2xl, centred) ───────────────────────────
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: _SearchInput(
                    controller: _searchController,
                    onChanged: widget.onSearch,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // ── Right-side actions ───────────────────────────────────────────
            _NavIconButton(
              icon: Icons.calendar_month_outlined,
              tooltip: 'Schedule',
              onPressed: widget.onScheduled,
            ),
            if (widget.isLoggedIn) ...[
              const SizedBox(width: 4),
              _NavIconButton(
                icon: Icons.video_library_outlined,
                tooltip: 'My Watchlist',
                onPressed: widget.onWatchlist,
              ),
            ],
            const SizedBox(width: 4),
            _UserButton(
              isLoggedIn: widget.isLoggedIn,
              onPressed: widget.onLogin,
            ),
            const SizedBox(width: 4),
            _NavIconButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              onPressed: widget.onSettings,
            ),

            // ── Window controls ──────────────────────────────────────────────
            // Mirrors the `border-l border-border pl-4` group in NavBar.svelte.
            const _NavDivider(),
            _WindowButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimise',
              onPressed: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: _isMaximised
                  ? Icons
                        .filter_none_rounded // restore icon
                  : Icons.crop_square_rounded, // maximise icon
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
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _NavLogo
// ════════════════════════════════════════════════════════════════════════════

/// "AniStream" wordmark — navigates home on tap.
///
/// Mirrors the `<button onclick={onHome}>` block in NavBar.svelte, including
/// the `group-hover:text-white transition-colors` title animation.
class _NavLogo extends StatefulWidget {
  final VoidCallback? onTap;
  const _NavLogo({this.onTap});

  @override
  State<_NavLogo> createState() => _NavLogoState();
}

class _NavLogoState extends State<_NavLogo> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: _hovered ? Colors.white : AppPalette.textMain,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          child: const Text('AniStream'),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _SearchInput
// ════════════════════════════════════════════════════════════════════════════

/// Search field with a leading icon and a primary focus ring.
///
/// Mirrors the `<input class="rounded-full bg-surface border-border
/// focus:ring-2 focus:ring-primary …">` in NavBar.svelte.
class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _SearchInput({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppPalette.textMain, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search for anime by title...',
        hintStyle: const TextStyle(color: AppPalette.textMuted, fontSize: 14),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 14, right: 10),
          child: Icon(
            Icons.search_rounded,
            color: AppPalette.textMuted,
            size: 20,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),
        filled: true,
        fillColor: AppPalette.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _NavIconButton
// ════════════════════════════════════════════════════════════════════════════

/// Generic icon button used for Schedule and Settings.
///
/// Mirrors the `hover:text-primary transition-colors` pattern on every
/// non-user icon button in NavBar.svelte.
class _NavIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  State<_NavIconButton> createState() => _NavIconButtonState();
}

class _NavIconButtonState extends State<_NavIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              widget.icon,
              color: _hovered ? AppPalette.primary : AppPalette.textMuted,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _UserButton
// ════════════════════════════════════════════════════════════════════════════

/// Login / logout button that mirrors the stateful colour logic in
/// NavBar.svelte:
///   • logged out → muted, hover → main
///   • logged in  → green (statusReleasing), hover → red (signals log-out)
class _UserButton extends StatefulWidget {
  final bool isLoggedIn;
  final VoidCallback? onPressed;

  const _UserButton({required this.isLoggedIn, this.onPressed});

  @override
  State<_UserButton> createState() => _UserButtonState();
}

class _UserButtonState extends State<_UserButton> {
  bool _hovered = false;

  Color get _iconColor {
    if (widget.isLoggedIn) {
      return _hovered ? AppPalette.statusCancelled : AppPalette.statusReleasing;
    }
    return _hovered ? AppPalette.textMain : AppPalette.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.isLoggedIn ? 'Log out of AniList' : 'Log in to AniList',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.person_outline_rounded,
              color: _iconColor,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _WindowButton
// ════════════════════════════════════════════════════════════════════════════

/// Minimise / Maximise-Restore / Close button.
///
/// [hoverColor] defaults to [AppPalette.textMain]. Pass
/// [AppPalette.accent] for Maximise and [AppPalette.statusCancelled] for
/// Close, matching the `hover:text-accent` / `hover:text-red-400`
/// transitions in NavBar.svelte.
class _WindowButton extends StatefulWidget {
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
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              widget.icon,
              color: _hovered
                  ? (widget.hoverColor ?? AppPalette.textMain)
                  : AppPalette.textMuted,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _NavDivider
// ════════════════════════════════════════════════════════════════════════════

/// Vertical separator between action icons and window controls.
/// Mirrors the `border-l border-border pl-4` wrapper in NavBar.svelte.
class _NavDivider extends StatelessWidget {
  const _NavDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(width: 1, height: 20, color: AppPalette.border),
    );
  }
}
