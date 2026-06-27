import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'app.dart';
import 'features/pip/pip_args.dart';
import 'features/pip/pip_player_window.dart';

void main() async {
  // 1. Initialize Flutter Engine
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Video Player Engine
  MediaKit.ensureInitialized();

  // 3. Initialize Native Desktop Window
  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  if (isDesktop) await windowManager.ensureInitialized();
  final windowController = await WindowController.fromCurrentEngine();
  final pipArgs = PipArgs.fromRaw(windowController.arguments);
  if (pipArgs.isPip) {
    runApp(PipPlayerWindow(args: pipArgs));
    return; // ── skip all the normal main-window setup below ──
  }
  if (isDesktop) {
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
  // 4. Boot App
  runApp(const AniStreamApp());
}
