import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_auth_service.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../shared/widgets/mouse_back_forward_listener.dart';
import '../anime_details/anime_details_screen.dart';
import '../home/home_screen.dart';
import '../schedule/scheduled_screen.dart';
import '../search/search_results_screen.dart';
import '../settings/settings_menu.dart';
import '../watchlist/watchlist_screen.dart';
import 'controllers/navigation_controller.dart';
import 'widgets/navbar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _auth = AnilistAuthService();
  late final NavigationController _nav;

  bool _isLoggedIn = false;
  bool _loginBusy = false;
  String _searchQuery = '';
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _nav = NavigationController(
      buildHome: () => HomeScreen(onSelectAnime: _handleSelectAnime),
    );
    _nav.addListener(_clearFocusForNewPage);
    unawaited(_restoreSession());
  }

  // Clears whatever currently holds focus — typically the navbar control
  // just pressed to trigger this navigation — before the new page's
  // widgets mount. Flutter's autofocus only fires when nothing in a
  // widget's nearest focus scope is already focused; without this, that
  // navbar control would still hold focus by the time the new page's own
  // autofocus:true target checks for it, and autofocus would silently
  // lose. Deliberately synchronous, not a post-frame callback:
  // notifyListeners() runs this before the setState-driven rebuild that
  // actually mounts the new page happens, so the clear is guaranteed to
  // land first.
  //
  // Doing this via an explicit unfocus, rather than a dedicated
  // FocusScopeNode around the body, keeps the body in the same focus
  // scope as AniStreamNavBar. Flutter's own directional traversal — which
  // DpadRegion's escape behavior builds on — only considers candidates
  // within the nearest enclosing focus scope, so a scope boundary around
  // the body would cap every DpadRegion inside it from ever escaping past
  // it, regardless of how those regions are nested.
  void _clearFocusForNewPage() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _nav.removeListener(_clearFocusForNewPage);
    _nav.dispose();
    super.dispose();
  }

  void _handleSelectAnime(Anime anime) {
    _nav.navigateTo(AnimeDetailsScreen(anime: anime, onBack: _nav.goBack));
  }

  void _handleTextChange(String query) => setState(() => _searchQuery = query);

  void _handleGoHome() {
    _nav.goHome();
    setState(() => _searchQuery = '');
  }

  void _handleSubmit(String query) {
    FocusScope.of(context).unfocus();
    if (query.trim().isEmpty) {
      _handleGoHome();
      return;
    }
    _nav.navigateTo(
      SearchResultsScreen(query: query, onSelectAnime: _handleSelectAnime),
    );
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
      if (!mounted) return;
      setState(() => _isLoggedIn = false);
      if (_nav.current is WatchlistScreen) _nav.goHome();
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
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    return MouseBackForwardListener(
      onBack: _nav.goBack,
      onForward: _nav.goForward,
      child: PopScope(
        canPop: !_nav.canGoBack,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (didPop) return;
          _nav.goBack();
        },
        // Rebuilds whenever NavigationController's history changes.
        child: ListenableBuilder(
          listenable: _nav,
          builder: (context, _) {
            return Scaffold(
              backgroundColor: AppPalette.base,
              extendBodyBehindAppBar: true,
              appBar: AniStreamNavBar(
                searchQuery: _searchQuery,
                isLoggedIn: _isLoggedIn,
                isScrolled: _isScrolled,
                uiPerformanceMode: uiPerformanceMode,
                onHome: _handleGoHome,
                onSearch: _handleTextChange,
                onSubmitted: _handleSubmit,
                onSelectAnime: _handleSelectAnime,
                onScheduled: () => _nav.navigateTo(
                  ScheduledScreen(onSelectAnime: _handleSelectAnime),
                ),
                onWatchlist: () => _nav.navigateTo(
                  WatchlistScreen(onSelectAnime: _handleSelectAnime),
                ),
                onLogin: _handleLogin,
                // SettingsScope propagates saved changes automatically.
                onSettings: () => showSettingsMenu(context),
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
                  // _nav.current sits directly here — no FocusScope, no
                  // DpadRegion. Sharing the same focus scope
                  // AniStreamNavBar lives in is what lets directional
                  // escape reach 'navbar' from a screen's topmost region,
                  // the same single-hop way shelf-to-shelf escape already
                  // works: Flutter's own traversal only considers
                  // candidates within the nearest enclosing focus scope,
                  // so a scope boundary here would cap every DpadRegion
                  // inside it from ever escaping past it, regardless of
                  // nesting. See _clearFocusForNewPage's doc comment for
                  // how new-page autofocus still correctly wins over a
                  // stale navbar focus without that boundary.
                  child: _nav.current,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
