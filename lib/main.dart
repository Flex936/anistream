import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'features/pip/pip_args.dart';
import 'features/pip/pip_player_window.dart';

// ── Accept CLI args to instantly intercept the sub-window ──
void main(List<String> args) async {
  // 1. Initialize Flutter Engine
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Video Player Engine
  MediaKit.ensureInitialized();

  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // 3. Intercept PIP Window Spawn (Desktop ONLY)
  // desktop_multi_window passes 'multi_window' as the first argument when spawning a sub-window.
  if (isDesktop && args.isNotEmpty && args.first == 'multi_window') {
    final rawArgs = args.length > 2 ? args[2] : null;
    final pipArgs = PipArgs.fromRaw(rawArgs);

    if (pipArgs.isPip) {
      runApp(PipPlayerWindow(args: pipArgs));
      return; // ── skip all the normal main-window setup below ──
    }
  }

  // 4. Initialize Native Desktop Window
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
  }

  // 5. Boot App
  runApp(const AniStreamApp());
}
