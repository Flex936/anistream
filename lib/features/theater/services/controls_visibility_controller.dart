import 'dart:async';

import 'package:flutter/foundation.dart';

/// Auto-hide state machine for the theater controls. Discrete interactions go
/// through [registerActivity]; [beginInteraction]/[endInteraction] bracket a
/// drag and suspend the timer for its whole duration. Driven by
/// [playingStream]/[isPlaying] so both players share it.
class ControlsVisibilityController {
  final Stream<bool> playingStream;
  final bool Function() isPlaying;

  /// Read when the timer fires, so a sub-menu opened after arming blocks it.
  final bool Function() isSubMenuOpen;

  ControlsVisibilityController({
    required this.playingStream,
    required this.isPlaying,
    required this.isSubMenuOpen,
  }) {
    _playingSub = playingStream.listen(_onPlayingChanged);
  }

  static const Duration _hideDelay = Duration(seconds: 3);

  // See ARCHITECTURE.md § 3.
  final ValueNotifier<bool> visible = ValueNotifier<bool>(true);

  Timer? _hideTimer;
  bool _interactionInProgress = false;
  late final StreamSubscription<bool> _playingSub;

  /// Reveals the controls and restarts the countdown; cheap if already visible.
  void registerActivity() {
    visible.value = true;
    _armTimer();
  }

  /// Suspends the hide timer for a seekbar/volume drag until [endInteraction].
  void beginInteraction() {
    _interactionInProgress = true;
    _hideTimer?.cancel();
    visible.value = true;
  }

  /// Re-arms the countdown after a drag ends.
  void endInteraction() {
    _interactionInProgress = false;
    registerActivity();
  }

  /// Hides immediately for a background tap, even while paused.
  void hideNow() {
    _hideTimer?.cancel();
    visible.value = false;
  }

  void _onPlayingChanged(bool playing) {
    if (!playing) {
      // Paused: cancel any pending hide and show the controls, so they're
      // visible whenever nothing is counting down to hide them.
      _hideTimer?.cancel();
      visible.value = true;
    } else {
      _armTimer();
    }
  }

  void _armTimer() {
    _hideTimer?.cancel();
    if (_interactionInProgress) return;
    if (!isPlaying()) return;

    _hideTimer = Timer(_hideDelay, () {
      if (_interactionInProgress) return;
      if (!isPlaying()) return;
      if (isSubMenuOpen()) return;
      visible.value = false;
    });
  }

  void dispose() {
    _hideTimer?.cancel();
    unawaited(_playingSub.cancel());
    visible.dispose();
  }
}
