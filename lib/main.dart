import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';
import 'features/pip/pip_args.dart';
import 'features/pip/pip_player_window.dart';

// ── Accept CLI args to instantly intercept the sub-window ──
void main(List<String> args) async {
  // 1. Initialize Flutter Engine
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize logging FIRST — before anything else runs — so that any
  // boot-time crash (native window init, media_kit init, etc.) is still
  // captured to disk. This also installs FlutterError/PlatformDispatcher
  // hooks and desktop signal handlers (see app_logger.dart for details).
  await AppLogger.init();

  // 3. Run everything else inside a guarded zone so uncaught async errors
  // anywhere in the app get logged (and flushed) instead of silently
  // vanishing — this matters most in a release build with no console.
  runZonedGuarded(
    () => _bootstrap(args),
    (error, stack) => AppLogger.e('main', 'Uncaught zone error', error, stack),
  );
}

Future<void> _bootstrap(List<String> args) async {
  // Initialize Video Player Engine
  MediaKit.ensureInitialized();
  AppLogger.i('main', 'MediaKit initialized');

  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // Intercept PIP Window Spawn (Desktop ONLY)
  // desktop_multi_window passes 'multi_window' as the first argument when spawning a sub-window.
  if (isDesktop && args.isNotEmpty && args.first == 'multi_window') {
    final rawArgs = args.length > 2 ? args[2] : null;
    final pipArgs = PipArgs.fromRaw(rawArgs);

    if (pipArgs.isPip) {
      AppLogger.i('main', 'Spawning PIP sub-window');
      runApp(PipPlayerWindow(args: pipArgs));
      return; // ── skip all the normal main-window setup below ──
    }
  }

  // Initialize Native Desktop Window
  if (isDesktop) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      title: 'AniStream',
      minimumSize: Size(
        1000,
        700,
      ), // Prevents the UI from crushing on tiny screens
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
    AppLogger.i('main', 'Desktop window initialized');
  }

  // Boot App
  AppLogger.i('main', 'Booting AniStreamApp');
  runApp(const AniStreamApp());
}
