import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/input/input_mode_controller.dart';
import 'core/logging/app_logger.dart';

// ── Accept CLI args (kept for forward compatibility with the Flutter
// tool's own launch args; PIP's 'multi_window' interception has been
// removed entirely — this app no longer spawns secondary windows). ──
void main(List<String> args) async {
  // Run everything — including binding initialization — inside the SAME
  // zone that `runApp()` will later execute in. Previously
  // `WidgetsFlutterBinding.ensureInitialized()` ran in the root zone while
  // `runApp()` (inside `_bootstrap`) ran inside `runZonedGuarded`'s child
  // zone, which is exactly the "Zone mismatch" Flutter warns about —
  // zone-specific state (like the error zone used for reporting) could
  // inconsistently reflect one zone or the other.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize logging FIRST — before anything else runs — so that any
      // boot-time crash (native window init, media_kit init, etc.) is still
      // captured to disk. This also installs FlutterError/PlatformDispatcher
      // hooks and desktop signal handlers (see app_logger.dart for details).
      await AppLogger.init();

      await _bootstrap(args);
    },
    (error, stack) => AppLogger.e('main', 'Uncaught zone error', error, stack),
  );
}

Future<void> _bootstrap(List<String> args) async {
  // Initialize Video Player Engine
  MediaKit.ensureInitialized();
  AppLogger.i('main', 'MediaKit initialized');

  // Resolve TV/D-Pad input mode before the first frame — awaited here
  // rather than left to InputModeScope's initState so a real Android TV
  // never renders even one frame in "pointer" mode before flipping over.
  await InputModeController.instance.init();
  AppLogger.i(
    'main',
    'Input mode resolved (isTvPlatform: ${InputModeController.instance.isTvPlatform})',
  );

  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // Initialize Native Desktop Window
  if (isDesktop) {
    await windowManager.ensureInitialized();

    final WindowOptions windowOptions = const WindowOptions(
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
