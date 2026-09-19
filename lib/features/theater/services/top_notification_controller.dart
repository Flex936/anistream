import 'dart:async';

import 'package:flutter/material.dart';

/// Message/icon/color for one in-flow status toast — see
/// [TopNotificationController], and `TheaterTopNotification`
/// (widgets/theater_player.dart), the widget both `TheaterScreen` and
/// `ExoTheaterScreen` render this through.
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

/// Owns Theater's own in-flow status toast — the AniList "Progress saved"
/// confirmation and the auto-skip "Skipping Opening in 2s..." countdown
/// both go through this controller on both `TheaterScreen` (media_kit)
/// and `ExoTheaterScreen` (video_player), instead of either screen
/// hand-rolling its own timer/state for the same behavior. Neither
/// `AutoSkipController` nor `AnilistTrackerService` needs to know this
/// class exists — both are already player-agnostic and only ever report
/// arming/success/failure via a plain callback, which each screen wires
/// straight into [show].
///
/// [notification] is a `ValueNotifier`, the same shape
/// `ControlsVisibilityController.visible` and
/// `PlaybackStallController.visible` already use — a caller wraps only
/// the small notification subtree in a `ValueListenableBuilder` instead
/// of rebuilding the whole screen on every toast.
class TopNotificationController {
  static const Duration _kDuration = Duration(seconds: 4);

  final ValueNotifier<TopNotificationData?> notification =
      ValueNotifier<TopNotificationData?>(null);

  Timer? _timer;

  /// Shows [message] with [icon]/[iconColor], auto-clearing after a fixed
  /// duration. A second call while one is already showing replaces it
  /// outright (and restarts the auto-clear countdown) rather than
  /// queuing.
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

  /// Cancels whatever auto-clear timer is currently pending without
  /// touching [notification]'s current value or disposing it. Used
  /// during a screen's teardown to stop a stray timer from firing after
  /// teardown has started, while still allowing a late-arriving [show]
  /// call (e.g. `AnilistTrackerService.flushPendingCommit`, awaited
  /// during that same teardown) to display normally right up until
  /// [dispose].
  void cancelPendingHide() {
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
    notification.dispose();
  }
}
