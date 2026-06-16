// lib/screens/app_shell.dart
//
// Root application shell for AniStream.

import 'dart:async'; // Needed for the debounce timer
import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/search_results_screen.dart';
import "../theme/app_palette.dart";
import '../../widgets/navbar.dart';
import '../../widgets/settings_menu.dart';

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
  Widget _currentView = const HomeScreen();
  bool _isLoggedIn = false;
  String _searchQuery = '';

  // Prevents API spam by waiting 500ms after the user stops typing
  Timer? _searchDebounce;

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateTo(Widget view) => setState(() => _currentView = view);

  void _handleSearch(String query) {
    setState(() => _searchQuery = query);

    // Cancel any existing timer if the user is still typing
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    // If the search is empty, immediately route back to the home screen
    if (query.trim().isEmpty) {
      _navigateTo(const HomeScreen());
      return;
    }

    // Wait 500ms after the last keystroke before hitting the AniList API
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _navigateTo(SearchResultsScreen(query: query));
    });
  }

  void _handleLogin() {
    // TODO: Trigger AniList OAuth flow
    setState(() => _isLoggedIn = !_isLoggedIn);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.base,

      appBar: AniStreamNavBar(
        searchQuery: _searchQuery,
        isLoggedIn: _isLoggedIn,
        onHome: () {
          // Clear the search field when navigating home via the logo
          setState(() => _searchQuery = '');
          _navigateTo(const HomeScreen());
        },
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
