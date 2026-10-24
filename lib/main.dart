import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/deep_link/deep_link_server.dart';
import 'core/input/input_mode_controller.dart';
import 'core/logging/app_logger.dart';

// Accepts CLI args (kept for forward compatibility with the Flutter
// tool's own launch args).
void main(List<String> args) {
  // Binding init and `runApp()` share one zone, since zone-specific state (the
  // error zone) must reflect one zone throughout. `main` stays non-`async`: the
  // zone runs for the app's lifetime with nothing meaningful to await, so the
  // call is wrapped in `unawaited()` to satisfy `avoid_void_async` instead of
  // given a `Future<void>` signature.
  unawaited(
    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();

        // Logging initializes first so a boot-time crash is still captured to
        // disk; this also installs the uncaught-error and signal hooks (see
        // `app_logger.dart`).
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

  // Resolved before the first frame, awaited here rather than left to
  // `InputModeScope.initState`, so a real Android TV never renders one frame in
  // "pointer" mode first.
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
      ),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    );

    // Deliberately not awaited: the native window stays hidden until this
    // callback's `show()` reveals it already maximized, so awaiting the whole
    // call here would block `runApp()` until then.
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

  // Desktop-only loopback listener for the browser extension companion
  // (ARCHITECTURE.md § 8); not awaited since binding a local port is
  // near-instant and nothing later depends on it.
  if (isDesktop) {
    unawaited(DeepLinkServer.instance.start());
  }

  // Called before the window-show sequence completes, so Flutter has a real
  // frame on the way to the surface before `show()`/`focus()` reveal it.
  AppLogger.i('main', 'Booting AniStreamApp');
  runApp(const AniStreamApp());
}