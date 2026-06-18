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
import '../services/anilist_auth_service.dart';
import 'watchlist_screen.dart';
import 'scheduled_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
//  AppShell
// ════════════════════════════════════════════════════════════════════════════

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _auth = AnilistAuthService();
  // The screen currently filling the Scaffold body.
  late Widget _currentView;

  // The screen we came from — used by _handleBack to go one level up.
  // null when we are already at the root (HomeScreen).
  Widget? _previousView;

  bool _isLoggedIn = false;
  bool _loginBusy = false;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // Build the initial view with the select callback already wired in.
    _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
    _restoreSession();
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

  void _goHome() {
    setState(() {
      _searchQuery = '';
      _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
      _previousView = null;
    });
  }

  @override
  void dispose() {
    // FIX: Always cancel timers to prevent memory leaks
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final token = await _auth.getStoredToken();
    if (token != null && mounted) {
      AnilistApiService.setToken(token);
      setState(() => _isLoggedIn = true);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  Auth
  // ════════════════════════════════════════════════════════════════════════

  /// Toggles login / logout.
  ///
  /// Login:  opens a browser window (AniList OAuth), waits for the token to
  ///         be captured by [AnilistAuthService], then updates API + UI state.
  ///
  /// Logout: clears the stored token, wipes the API auth state, and navigates
  ///         away from the watchlist if it is the current view.
  Future<void> _handleLogin() async {
    if (_loginBusy) return; // ignore double-taps while browser is open

    if (_isLoggedIn) {
      // ── Logout ──────────────────────────────────────────────────────────
      await _auth.logout();
      AnilistApiService.clearToken();
      setState(() => _isLoggedIn = false);

      // If the user was on the watchlist, take them home.
      if (_currentView is WatchlistScreen) _goHome();
      return;
    }

    // ── Login ──────────────────────────────────────────────────────────────
    setState(() => _loginBusy = true);
    try {
      final token = await _auth.login();
      if (!mounted) return;

      if (token != null) {
        AnilistApiService.setToken(token);
        setState(() => _isLoggedIn = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppPalette.statusCancelled,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loginBusy = false);
    }
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
        onScheduled: () => {
          _navigateTo(ScheduledScreen(onSelectAnime: _handleSelectAnime)),
        },
        onWatchlist: () =>
            _navigateTo(WatchlistScreen(onSelectAnime: _handleSelectAnime)),
        onLogin: _handleLogin,
        onSettings: () => showSettingsMenu(context),
      ),
      body: _currentView,
    );
  }
}
