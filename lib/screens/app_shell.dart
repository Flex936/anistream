// lib/screens/app_shell.dart
//
// Root application shell for AniStream.
// Owns the persistent NavBar and switches the body between screens without
// creating new Navigator routes — so the NavBar is always visible.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/anilist_api.dart';
import '../theme/app_palette.dart';
import '../widgets/navbar.dart';
import '../widgets/settings_menu.dart';
import 'anime_details_screen.dart';
import 'home_screen.dart';
import 'search_results_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
//  AppShell
// ════════════════════════════════════════════════════════════════════════════

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // The screen currently filling the Scaffold body.
  late Widget _currentView;

  // The screen we came from — used by _handleBack to go one level up.
  // null when we are already at the root (HomeScreen).
  Widget? _previousView;

  bool _isLoggedIn = false;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // Build the initial view with the select callback already wired in.
    _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Pushes [view] onto the one-level history stack and displays it.
  void _navigateTo(Widget view) {
    setState(() {
      _previousView = _currentView;
      _currentView = view;
    });
  }

  /// Called when an AnimeCard is tapped anywhere in the app.
  /// Keeps navigation inside the shell so the NavBar stays visible.
  void _handleSelectAnime(Anime anime) {
    _navigateTo(AnimeDetailsScreen(anime: anime, onBack: _handleBack));
  }

  /// Called by the "Back" button inside AnimeDetailsScreen.
  void _handleBack() {
    setState(() {
      _currentView =
          _previousView ?? HomeScreen(onSelectAnime: _handleSelectAnime);
      _previousView = null;
    });
  }

  void _handleSearch(String query) {
    setState(() => _searchQuery = query);
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    if (query.trim().isEmpty) {
      // Clear → return home
      setState(() {
        _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
        _previousView = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _navigateTo(
        SearchResultsScreen(query: query, onSelectAnime: _handleSelectAnime),
      );
    });
  }

  @override
  void dispose() {
    // FIX: Always cancel timers to prevent memory leaks
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _handleLogin() {
    // TODO: Trigger AniList OAuth flow; set _isLoggedIn = true on success.
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
          setState(() => _searchQuery = '');
          setState(() {
            _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
            _previousView = null;
          });
        },
        onSearch: _handleSearch,
        onScheduled: () {
          /* TODO: _navigateTo(const ScheduleScreen()) */
        },
        onWatchlist: () {
          /* TODO: _navigateTo(const WatchlistScreen()) */
        },
        onLogin: _handleLogin,
        onSettings: () => showSettingsMenu(context),
      ),
      body: _currentView,
    );
  }
}
