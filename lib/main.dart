import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/input/input_mode_controller.dart';
import 'core/logging/app_logger.dart';

// Accepts CLI args (kept for forward compatibility with the Flutter
// tool's own launch args).
void main(List<String> args) {
  // Runs everything, including binding initialization, inside the same
  // zone that `runApp()` executes in — `WidgetsFlutterBinding.ensureInitialized()`
  // and `runApp()` (inside `_bootstrap`) both need to share a zone, since
  // zone-specific state (like the error zone used for reporting) must
  // consistently reflect one zone, not straddle two.
  //
  // `main` itself is deliberately NOT `async`: the zone runs for the
  // lifetime of the app (there's nothing meaningful to await — the
  // returned Future only completes if the zone's body itself returns,
  // which for a running Flutter app it never does), so the call is
  // explicitly marked `unawaited()` rather than given a `Future<void>`
  // signature purely to satisfy avoid_void_async.
  unawaited(
    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();

        // Logging initializes first, before anything else runs, so that
        // any boot-time crash (native window init, media_kit init, etc.)
        // is still captured to disk. This also installs
        // FlutterError/PlatformDispatcher hooks and desktop signal
        // handlers (see app_logger.dart for details).
        await AppLogger.init();

        await _bootstrap(args);
      },
      (error, stack) =>
          AppLogger.e('main', 'Uncaught zone error', error, stack),
    ),
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

    // Deliberately not awaited. The native window stays hidden (see the
    // "hide until ready" patches in windows/runner and linux/runner)
    // until this callback's show() call reveals it, already maximized.
    // Awaiting the whole call here would block runApp() below until the
    // window is already shown/maximized/focused — before Flutter has
    // built a widget tree or rendered a single frame onto its surface.
    unawaited(
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
        AppLogger.i('main', 'Desktop window shown (maximized)');
      }),
    );
    AppLogger.i('main', 'Desktop window initialization scheduled');
  }

  // Boot App. Called immediately rather than after the window-show
  // sequence above completes, so Flutter has a real frame on the way to
  // the window's surface well before show()/focus() ever reveal it.
  AppLogger.i('main', 'Booting AniStreamApp');
  runApp(const AniStreamApp());
}
