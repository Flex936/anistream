import 'dart:async';

import 'package:flutter/material.dart';

/// Content of one status toast; see [TopNotificationController].
@immutable
class TopNotificationData {
  final String message;
  final IconData icon;
  final Color iconColor;

  const TopNotificationData({
    required this.message,
    required this.icon,
    required this.iconColor,
  });
}

/// Theater's in-flow status toast (AniList sync, auto-skip countdown), shared
/// by both theater screens.
class TopNotificationController {
  static const Duration _kDuration = Duration(seconds: 4);

  final ValueNotifier<TopNotificationData?> notification =
      ValueNotifier<TopNotificationData?>(null);

  Timer? _timer;

  /// Shows an auto-clearing toast; a new call replaces it instead of queuing.
  void show({
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    _timer?.cancel();
    notification.value = TopNotificationData(
      message: message,
      icon: icon,
      iconColor: iconColor,
    );
    _timer = Timer(_kDuration, () {
      notification.value = null;
    });
  }

  /// Cancels the pending auto-clear but leaves [notification] intact, so a
  /// [show] during teardown (e.g. `flushPendingCommit`) still displays.
  void cancelPendingHide() {
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
    notification.dispose();
  }
}
