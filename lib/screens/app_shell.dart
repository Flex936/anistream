import 'dart:async';
import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/search_results_screen.dart';
import '../theme/app_palette.dart';
import '../widgets/navbar.dart';
import '../widgets/settings_menu.dart';

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

  Timer? _searchDebounce;

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateTo(Widget view) {
    if (!mounted) return;
    setState(() => _currentView = view);
  }

  void _handleSearch(String query) {
    setState(() => _searchQuery = query);

    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    if (query.trim().isEmpty) {
      _navigateTo(const HomeScreen());
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _navigateTo(SearchResultsScreen(query: query));
    });
  }

  void _handleLogin() {
    setState(() => _isLoggedIn = !_isLoggedIn);
  }

  @override
  void dispose() {
    // FIX: Always cancel timers to prevent memory leaks
    _searchDebounce?.cancel();
    super.dispose();
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
          setState(() => _searchQuery = '');
          _navigateTo(const HomeScreen());
        },
        onSearch: _handleSearch,
        onScheduled: () {
          // TODO: Implement ScheduleScreen
        },
        onWatchlist: () {
          // TODO: Implement WatchlistScreen
        },
        onLogin: _handleLogin,
        onSettings: () => showSettingsMenu(context),
      ),
      body: _currentView,
    );
  }
}
