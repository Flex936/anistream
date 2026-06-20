import 'package:flutter/material.dart';

import '../../features/shell/app_shell.dart';
import '../theme/app_palette.dart';

abstract final class AppRouter {
  static const String initial = '/';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case initial:
        return MaterialPageRoute(
          builder: (_) => const AppShell(),
          settings: settings,
        );

      // Add future routes here (e.g., '/login', '/onboarding')

      default:
        // Fallback route for safety
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            backgroundColor: AppPalette.base,
            body: Center(
              child: Text(
                'Route not found!',
                style: TextStyle(
                  color: AppPalette.statusCancelled,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        );
    }
  }
}
