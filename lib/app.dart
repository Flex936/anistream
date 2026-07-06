import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_palette.dart';
import 'core/router/app_router.dart';
import 'core/logging/app_logger.dart';

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
    // Lets AppLogger flush to disk when the app is backgrounded, put to
    // sleep, or torn down by the OS — the cases a plain process-exit hook
    // can't see on mobile.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.onAppLifecycleStateChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Belt-and-braces final flush for a normal widget-tree teardown.
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
        brightness: Brightness.dark,
        // Globally sets the background so you don't need it on individual Scaffolds!
        scaffoldBackgroundColor: AppPalette.base,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.dark,
        ),
      ),
      // Hands off navigation responsibility to our dedicated router
      initialRoute: AppRouter.initial,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
