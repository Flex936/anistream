import 'package:flutter/material.dart';

import 'core/theme/app_palette.dart';
import 'core/router/app_router.dart';

class AniStreamApp extends StatelessWidget {
  const AniStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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