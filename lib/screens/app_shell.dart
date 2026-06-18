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
  late Widget _currentView;
  Widget? _previousView;

  bool _isLoggedIn = false;
  bool _loginBusy = false;
  String _searchQuery = '';
  Timer? _searchDebounce;
  
  // ── NEW: Tracks if the current screen is scrolled down ──
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
    _restoreSession();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateTo(Widget view) {
    setState(() {
      _previousView = _currentView;
      _currentView = view;
      _isScrolled = false; // Reset glassmorphism when changing screens
    });
  }

  void _handleSelectAnime(Anime anime) {
    _navigateTo(AnimeDetailsScreen(anime: anime, onBack: _handleBack));
  }

  void _handleBack() {
    setState(() {
      _currentView = _previousView ?? HomeScreen(onSelectAnime: _handleSelectAnime);
      _previousView = null;
      _isScrolled = false; // Reset glassmorphism when going back
    });
  }

  void _handleSearch(String query) {
    setState(() => _searchQuery = query);
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    if (query.trim().isEmpty) {
      _goHome();
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
      _isScrolled = false; // Reset glassmorphism going home
    });
  }

  @override
  void dispose() {
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

  Future<void> _handleLogin() async {
    if (_loginBusy) return; 

    if (_isLoggedIn) {
      await _auth.logout();
      AnilistApiService.clearToken();
      setState(() => _isLoggedIn = false);
      if (_currentView is WatchlistScreen) _goHome();
      return;
    }

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
      // ── CRITICAL: Allows the content to scroll *underneath* the NavBar ──
      extendBodyBehindAppBar: true, 
      
      appBar: AniStreamNavBar(
        searchQuery: _searchQuery,
        isLoggedIn: _isLoggedIn,
        isScrolled: _isScrolled, // ── NEW: Tells NavBar to apply frosting ──
        onHome: _goHome,
        onSearch: _handleSearch,
        onScheduled: () => {
          _navigateTo(ScheduledScreen(onSelectAnime: _handleSelectAnime)),
        },
        onWatchlist: () => _navigateTo(WatchlistScreen(onSelectAnime: _handleSelectAnime)),
        onLogin: _handleLogin,
        onSettings: () => showSettingsMenu(context),
      ),
      
      // ── NEW: Magically intercepts scroll data from any screen loaded inside it ──
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          // Only trigger on the main vertical scroll axis
          if (notification.depth == 0) {
            final isScrolled = notification.metrics.pixels > 20;
            if (isScrolled != _isScrolled) {
              // We use postFrameCallback to avoid updating state while Flutter is in the middle of drawing
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _isScrolled = isScrolled);
              });
            }
          }
          return false; // Return false so the scroll list still works normally
        },
        child: _currentView,
      ),
    );
  }
}