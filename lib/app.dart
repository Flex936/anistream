import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dpad/dpad.dart';

import 'core/theme/app_palette.dart';
import 'core/router/app_router.dart';
import 'core/logging/app_logger.dart';
import 'core/settings/settings_scope.dart';
import 'core/input/input_mode_scope.dart';

class AniStreamApp extends StatefulWidget {
  const AniStreamApp({super.key});

  @override
  State<AniStreamApp> createState() => _AniStreamAppState();
}

class _AniStreamAppState extends State<AniStreamApp>
    with WidgetsBindingObserver {
  // ── Lets _handleDpadBack reach the real Navigator from a callback that
  // has no BuildContext of its own. Deliberately NOT using
  // MaterialApp.builder's own `context` for this: that context sits
  // ABOVE the Navigator this app pushes routes on (builder wraps AROUND
  // the routed content), so Navigator.of(context) called with it can't
  // reliably find the Navigator below. A navigatorKey sidesteps that
  // entirely. ──
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.onAppLifecycleStateChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppLogger.dispose();
    super.dispose();
  }

  // ── Deliberately does NOT reimplement back-navigation. maybePop() walks
  // the exact same PopScope chain the system back gesture/key already
  // triggers — which means AppShell's own
  // `PopScope(canPop: !_nav.canGoBack, onPopInvokedWithResult: ...)` is
  // still the one and only place that decides what "back" actually does
  // (redirect into NavigationController.goBack(), pop a pushed route like
  // TheaterScreen/AnimeDetailsScreen, or — at Home, with nothing left —
  // let the pop through, which is the normal "back at the app's root
  // exits to the launcher" behavior, not a bug). This just gives the
  // D-Pad remote's dedicated Back key the same entry point the manifest
  // fix already gave the system gesture.
  //
  // Always returning true tells Dpad "the app handled this back-press" —
  // either something popped, or PopScope already correctly decided
  // nothing needed to change. There's nothing further for Dpad itself to
  // do in either case. ──
  bool _handleDpadBack() {
    _navigatorKey.currentState?.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
      },
      title: 'AniStream',
      theme: ThemeData(
        scaffoldBackgroundColor: AppPalette.base,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.dark,
        ),
      ),
      // ── Dpad.wrap() is now the outermost layer, matching its documented
      // root-install pattern (`MaterialApp(builder: Dpad.wrap())`).
      // InputModeScope + SettingsScope keep their EXACT prior relative
      // nesting, just pushed one level in. InputModeScope — and by
      // extension InputModeController and the native isTelevision channel
      // beneath it — is still load-bearing for TheaterScreen and every
      // widget it hands dpadModeActive to (Seekbar, TheaterControls,
      // TheaterSettingsMenu, BatchEpisodePickerOverlay), plus
      // settings_components.dart, calendar_card.dart, watchlist_cards.dart,
      // hero_banner.dart, episode_tile.dart, and torrent_tile.dart, none of
      // which are migrated yet. It comes out in the phase that migrates
      // Theater — not before, or none of those files compile. ──
      builder: (context, child) => Dpad.wrap(
        theme: const DpadThemeData(scrollPadding: 24),
        debugOverlay: kDebugMode,
        onBack: _handleDpadBack,
      )(context, InputModeScope(child: SettingsScope(child: child!))),
      initialRoute: AppRouter.initial,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
