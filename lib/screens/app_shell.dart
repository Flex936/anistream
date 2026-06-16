// lib/screens/app_shell.dart
//
// Root application shell for AniStream.
// Replaces the top-level view-switching and NavBar logic that lived inside
// App.svelte in the Wails build.
//
// [AppShell] owns exactly one [AniStreamNavBar] and swaps the [body] when
// the user navigates. Every screen in the app is rendered inside this shell
// so the NavBar is always visible — matching the Svelte layout where
// <NavBar /> sat above the active view component in App.svelte.

import 'package:flutter/material.dart';

import '../screens/home_screen.dart'; // HomeScreen
import "../theme/app_palette.dart"; // AppPalette
import '../../widgets/navbar.dart'; // AniStreamNavBar
import '../../widgets/settings_menu.dart'; // showSettingsMenu

// ════════════════════════════════════════════════════════════════════════════
//  AppShell
// ════════════════════════════════════════════════════════════════════════════

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // ── View state ────────────────────────────────────────────────────────────
  // Starts on HomeScreen — the equivalent of DiscoveryView being the
  // default active view in App.svelte.
  Widget _currentView = const HomeScreen();
  bool _isLoggedIn = false;
  String _searchQuery = '';

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateTo(Widget view) => setState(() => _currentView = view);

  void _handleSearch(String query) {
    setState(() => _searchQuery = query);
    // TODO: _navigateTo(SearchResultsScreen(query: query));
  }

  void _handleLogin() {
    // TODO: Trigger AniList OAuth flow; set _isLoggedIn = true on success
    //       and _isLoggedIn = false on logout.
    setState(() => _isLoggedIn = !_isLoggedIn);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.base,

      // AniStreamNavBar is declared once here and persists across every
      // screen swap — the Flutter equivalent of <NavBar /> in App.svelte.
      appBar: AniStreamNavBar(
        searchQuery: _searchQuery,
        isLoggedIn: _isLoggedIn,
        onHome: () => _navigateTo(const HomeScreen()),
        onSearch: _handleSearch,
        onScheduled: () {
          // TODO: _navigateTo(const ScheduleScreen());
        },
        onWatchlist: () {
          // TODO: _navigateTo(const WatchlistScreen());
        },
        onLogin: _handleLogin,
        onSettings: () => showSettingsMenu(context),
      ),

      body: _currentView,
    );
  }
}
