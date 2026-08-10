import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/input/input_mode_scope.dart';
import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_scope.dart';
import 'core/theme/app_card_sizes.dart';
import 'core/theme/app_materials.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_radii.dart';
import 'core/theme/app_typography.dart';

class AniStreamApp extends StatefulWidget {
  const AniStreamApp({super.key});

  @override
  State<AniStreamApp> createState() => _AniStreamAppState();
}

class _AniStreamAppState extends State<AniStreamApp>
    with WidgetsBindingObserver {
  // Lets _handleDpadBack reach the real Navigator from a callback that
  // has no BuildContext of its own. Deliberately not using
  // MaterialApp.builder's own `context` for this: that context sits
  // above the Navigator this app pushes routes on (builder wraps around
  // the routed content), so Navigator.of(context) called with it can't
  // reliably find the Navigator below. A navigatorKey sidesteps that
  // entirely.
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
    unawaited(AppLogger.dispose());
    super.dispose();
  }

  // Deliberately does not reimplement back-navigation. maybePop() walks
  // the exact same PopScope chain the system back gesture/key already
  // triggers — which means AppShell's own
  // `PopScope(canPop: !_nav.canGoBack, onPopInvokedWithResult: ...)` is
  // still the one and only place that decides what "back" actually does
  // (redirect into NavigationController.goBack(), pop a pushed route like
  // TheaterScreen/AnimeDetailsScreen, or — at Home, with nothing left —
  // let the pop through, which is the normal "back at the app's root
  // exits to the launcher" behavior, not a bug). This gives the D-Pad
  // remote's dedicated Back key the same entry point the manifest gives
  // the system gesture.
  //
  // Always returning true tells Dpad "the app handled this back-press" —
  // either something popped, or PopScope already correctly decided
  // nothing needed to change. There's nothing further for Dpad itself to
  // do in either case.
  bool _handleDpadBack() {
    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      unawaited(navigator.maybePop());
    }
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
        // Named typography/radius/materials/card-size tokens, registered
        // once here and read anywhere below via `context.appTypography` /
        // `context.appRadii` / `context.appMaterials` /
        // `context.appCardSizes` (build_context_extensions.dart).
        extensions: const [
          AppTypography.standard,
          AppRadii.standard,
          AppMaterials.standardTiers,
          AppCardSizes.standard,
        ],
      ),
      // Dpad.wrap() is the outermost layer, matching its documented
      // root-install pattern (`MaterialApp(builder: Dpad.wrap())`).
      // InputModeScope + SettingsScope keep this relative nesting — it's
      // load-bearing for TheaterScreen and every widget it hands
      // dpadModeActive to (Seekbar, TheaterControls, TheaterSettingsMenu,
      // BatchEpisodePickerOverlay), plus settings_components.dart,
      // calendar_card.dart, watchlist_cards.dart, hero_banner.dart,
      // episode_tile.dart, and torrent_tile.dart.
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
