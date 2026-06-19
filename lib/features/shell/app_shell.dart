import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/anilist/models/anime.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../core/theme/app_palette.dart';
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
  late Widget _currentView;
  Widget? _previousView;

  bool _isLoggedIn = false;
  bool _loginBusy = false;
  String _searchQuery = '';
  
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
    _restoreSession();
  }

  void _navigateTo(Widget view) {
    setState(() {
      _previousView = _currentView;
      _currentView = view;
      _isScrolled = false; 
    });
  }

  void _handleSelectAnime(Anime anime) {
    _navigateTo(AnimeDetailsScreen(anime: anime, onBack: _handleBack));
  }

  void _handleBack() {
    setState(() {
      _currentView = _previousView ?? HomeScreen(onSelectAnime: _handleSelectAnime);
      _previousView = null;
      _isScrolled = false; 
    });
  }

  void _handleTextChange(String query) {
    setState(() => _searchQuery = query);
  }

  void _handleSubmit(String query) {
    FocusScope.of(context).unfocus();
    if (query.trim().isEmpty) {
      _goHome();
      return;
    }
    _navigateTo(SearchResultsScreen(query: query, onSelectAnime: _handleSelectAnime));
  }

  void _goHome() {
    setState(() {
      _searchQuery = '';
      _currentView = HomeScreen(onSelectAnime: _handleSelectAnime);
      _previousView = null;
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
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loginBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.base,
      extendBodyBehindAppBar: true, 
      appBar: AniStreamNavBar(
        searchQuery: _searchQuery,
        isLoggedIn: _isLoggedIn,
        isScrolled: _isScrolled,
        onHome: _goHome,
        onSearch: _handleTextChange,
        onSubmitted: _handleSubmit,
        onSelectAnime: _handleSelectAnime, 
        onScheduled: () => _navigateTo(ScheduledScreen(onSelectAnime: _handleSelectAnime)),
        onWatchlist: () => _navigateTo(WatchlistScreen(onSelectAnime: _handleSelectAnime)),
        onLogin: _handleLogin,
        onSettings: () => showSettingsMenu(context),
      ),
      body: NotificationListener<ScrollNotification>(
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
    );
  }
}