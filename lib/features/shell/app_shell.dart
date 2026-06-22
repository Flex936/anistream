import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/anilist/models/anime.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_service.dart';
import 'widgets/navbar.dart';
import '../settings/settings_menu.dart';
import '../anime_details/anime_details_screen.dart';
import '../home/home_screen.dart';
import '../search/search_results_screen.dart';
import '../../data/anilist/anilist_auth_service.dart';
import '../watchlist/watchlist_screen.dart';
import '../schedule/scheduled_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _auth = AnilistAuthService();

  late final List<Widget> _history;

  bool _isLoggedIn = false;
  bool _loginBusy = false;
  String _searchQuery = '';
  bool _isScrolled = false;

  bool _uiPerformanceMode = false;

  @override
  void initState() {
    super.initState();
    _history = [HomeScreen(onSelectAnime: _handleSelectAnime)];
    _restoreSession();
    _loadSettings();
  }

  // ── Reloads settings instantly ──
  Future<void> _loadSettings() async {
    final s = await SettingsService().load();
    if (mounted) setState(() => _uiPerformanceMode = s.uiPerformanceMode);
  }

  Widget get _currentView => _history.last;

  void _navigateTo(Widget view) {
    setState(() {
      _history.add(view);
      _isScrolled = false;
    });
  }

  bool _goBack() {
    if (_history.length <= 1) return false;
    setState(() {
      _history.removeLast();
      _isScrolled = false;
    });
    return true;
  }

  void _handleSelectAnime(Anime anime) {
    _navigateTo(AnimeDetailsScreen(anime: anime, onBack: _goBack));
  }

  void _handleTextChange(String query) => setState(() => _searchQuery = query);

  void _handleSubmit(String query) {
    FocusScope.of(context).unfocus();
    if (query.trim().isEmpty) {
      _goHome();
      return;
    }
    _navigateTo(
      SearchResultsScreen(query: query, onSelectAnime: _handleSelectAnime),
    );
  }

  void _goHome() {
    setState(() {
      _searchQuery = '';
      _history.clear();
      _history.add(HomeScreen(onSelectAnime: _handleSelectAnime));
      _isScrolled = false;
    });
  }

  Future<void> _restoreSession() async {
    final token = await _auth.getStoredToken();
    if (token != null && mounted) {
      AnilistQueryService.setToken(token);
      setState(() => _isLoggedIn = true);
    }
  }

  Future<void> _handleLogin() async {
    if (_loginBusy) return;

    if (_isLoggedIn) {
      await _auth.logout();
      AnilistQueryService.clearToken();
      setState(() => _isLoggedIn = false);
      if (_currentView is WatchlistScreen) _goHome();
      return;
    }

    setState(() => _loginBusy = true);
    try {
      final token = await _auth.login();
      if (!mounted) return;
      if (token != null) {
        AnilistQueryService.setToken(token);
        setState(() => _isLoggedIn = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppPalette.statusCancelled,
        ),
      );
    } finally {
      if (mounted) setState(() => _loginBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _history.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: AppPalette.base,
        extendBodyBehindAppBar: true,
        appBar: AniStreamNavBar(
          searchQuery: _searchQuery,
          isLoggedIn: _isLoggedIn,
          isScrolled: _isScrolled,
          uiPerformanceMode: _uiPerformanceMode,
          onHome: _goHome,
          onSearch: _handleTextChange,
          onSubmitted: _handleSubmit,
          onSelectAnime: _handleSelectAnime,
          onScheduled: () =>
              _navigateTo(ScheduledScreen(onSelectAnime: _handleSelectAnime)),
          onWatchlist: () =>
              _navigateTo(WatchlistScreen(onSelectAnime: _handleSelectAnime)),
          onLogin: _handleLogin,
          // ── Reload settings automatically when the menu closes ──
          onSettings: () async {
            await showSettingsMenu(context);
            _loadSettings();
          },
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification.depth == 0) {
                final isScrolled = notification.metrics.pixels > 20;
                if (isScrolled != _isScrolled) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _isScrolled = isScrolled);
                  });
                }
              }
              return false;
            },
            child: _currentView,
          ),
        ),
      ),
    );
  }
}
