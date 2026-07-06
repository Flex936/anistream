import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_palette.dart';
import 'core/router/app_router.dart';
import 'core/logging/app_logger.dart';
import 'core/settings/settings_scope.dart';

class AniStreamApp extends StatefulWidget {
  const AniStreamApp({super.key});

  @override
  State<AniStreamApp> createState() => _AniStreamAppState();
}

class _AniStreamAppState extends State<AniStreamApp>
    with WidgetsBindingObserver {
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
      },
      title: 'AniStream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppPalette.base,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.dark,
        ),
      ),
      // ── Wraps every route (and dialogs like the settings menu) in a
      // single shared settings source, replacing per-screen
      // SettingsService().load() boilerplate. ──
      builder: (context, child) => SettingsScope(child: child!),
      initialRoute: AppRouter.initial,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
