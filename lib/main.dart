import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';

void main() {
  // Ensures component bindings are ready before initialization
  WidgetsFlutterBinding.ensureInitialized();

  // Directs libmpv to spin up its native rendering context
  MediaKit.ensureInitialized();

  runApp(const AniStreamApp());
}

class AniStreamApp extends StatelessWidget {
  const AniStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniStream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppPalette.base, // Uses Claude's custom token!
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.dark,
        ),
      ),
      // Set the initial route to Claude's new Discovery page
      home: const HomeScreen(),
    );
  }
}
