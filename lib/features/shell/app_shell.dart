import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_auth_service.dart';
import '../../data/anilist/anilist_query_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../shared/widgets/mouse_back_forward_listener.dart';
import '../anime_details/anime_details_screen.dart';
import '../custom_stream/custom_stream_launcher.dart';
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

  // Dedicated focus scope for the routed page content, kept separate from
  // the nav bar's own ambient scope. Flutter autofocus only activates
  // when nothing else in a widget's nearest scope is already focused —
  // this boundary is what lets each page's own autofocus:true target
  // (HomeScreen's first carousel card, AnimeDetailsScreen's up-next
  // episode, etc.) win focus on every navigation, regardless of which
  // nav bar control was pressed to get here.
  final FocusScopeNode _bodyFocusScope = FocusScopeNode(
    debugLabel: 'AppShellBody',
  );

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
    _nav.addListener(_focusNewPage);
    unawaited(_restoreSession());
  }

  // Runs after every navigation, once the new page's widgets have
  // actually mounted, so its own autofocus target exists to receive
  // focus. requestFocus() on a scope with no currently-focused child
  // defers to normal autofocus resolution among its descendants — see
  // the field doc comment above.
  void _focusNewPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocusScope.requestFocus();
    });
  }

  @override
  void dispose() {
    _nav.removeListener(_focusNewPage);
    _bodyFocusScope.dispose();
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
                onCustomStream: () => launchCustomMagnetStream(context),
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
                  // Bare DpadRegion — default leave/leave edge behavior on
                  // both axes is what's wanted here: Up from the top of
                  // whichever screen is showing escapes this region
                  // entirely and lands on the best candidate outside it
                  // (AniStreamNavBar's own region, wrapped in navbar.dart),
                  // while Down/Left/Right with nothing beyond this region
                  // to find just no-op harmlessly. No memoryKey: _nav.current
                  // is a completely different widget subtree per section
                  // (Home's carousels vs. Watchlist's grid vs. Schedule's
                  // shelves), so a single "remembered position" at this
                  // outer level wouldn't mean anything — that memory
                  // belongs inside each screen's own regions instead (see
                  // HomeScreen).
                  //
                  // Wrapped in its own FocusScope (_bodyFocusScope, set
                  // above) so this region's focus state is independent of
                  // AniStreamNavBar's — see that field's doc comment for
                  // why that separation is what makes each page's own
                  // autofocus target actually win focus on navigation.
                  child: FocusScope(
                    node: _bodyFocusScope,
                    child: DpadRegion(child: _nav.current),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
