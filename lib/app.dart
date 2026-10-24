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
  // Lets `_handleDpadBack` reach the real Navigator with no `BuildContext` of
  // its own — `MaterialApp.builder`'s own context sits above the pushed
  // Navigator, so `Navigator.of` on it can't find it.
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

  // Deliberately does not reimplement back navigation: `maybePop()` walks the
  // same `PopScope` chain the system back gesture already triggers, so
  // `AppShell`'s own `PopScope` stays the one place that decides what back
  // does. Always returns `true` — either something popped, or `PopScope`
  // already decided nothing needed to change.
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
        extensions: const [
          AppTypography.standard,
          AppRadii.standard,
          AppMaterials.standardTiers,
          AppCardSizes.standard,
        ],
      ),
      // Order matters: `InputModeScope` must wrap `SettingsScope` here
      // (ARCHITECTURE.md § 3).
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