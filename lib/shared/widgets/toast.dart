import 'package:flutter/material.dart';
import '../../core/settings/settings_scope.dart';
import 'glass_toast_content.dart';

// Apple-style premium glass toast (bottom). Theater's own top-of-screen
// status messages (TheaterScreen and ExoTheaterScreen alike) render
// through TheaterTopNotification (features/theater/widgets/
// theater_player.dart) instead, fed by a shared TopNotificationController
// (features/theater/services/top_notification_controller.dart), since
// they need to sit inside each screen's own Stack alongside its top bar
// rather than above it via Overlay.

class AppleSnackBar {
  static void show({
    required BuildContext context,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
        content: _BottomToastWidget(
          message: message,
          icon: icon,
          iconColor: iconColor,
        ),
      ),
    );
  }
}

class _BottomToastWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color iconColor;

  const _BottomToastWidget({
    required this.message,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    return Align(
      alignment: Alignment.bottomCenter,
      child: GlassToastContent(
        message: message,
        icon: icon,
        iconColor: iconColor,
        uiPerformanceMode: uiPerformanceMode,
      ),
    );
  }
}
