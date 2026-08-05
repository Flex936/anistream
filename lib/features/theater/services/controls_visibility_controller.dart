import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Owns the "auto-hide the theater controls after inactivity" state
/// machine. Replaces the roughly a dozen scattered
/// `_startHideControlsTimer()` call sites that used to live directly on
/// `_TheaterScreenState` — every interaction (a tap, a keypress, a button
/// press, a mouse move) now goes through exactly one of the three entry
/// points below instead of re-implementing "cancel then reschedule" at
/// each call site.
///
/// [registerActivity] is the entry point for discrete interactions — a
/// tap, a keypress, a button press. [beginInteraction]/[endInteraction]
/// bracket a CONTINUOUS interaction (a seekbar or volume-slider drag) and
/// explicitly suspend the hide timer for its full duration, rather than
/// relying on the interaction's own per-update callback happening to
/// re-ping [registerActivity] often enough on its own — a mechanism that's
/// only ever true by coincidence of how a given widget's drag callback
/// happens to be wired today, not something a future change to either
/// widget is obligated to preserve.
///
/// Visibility is exposed as [visible], a [ValueNotifier<bool>], rather
/// than a callback or a full app-wide `ChangeNotifier` surface — this lets
/// `theater_screen.dart` wrap ONLY the small subtree that actually needs
/// to redraw on show/hide in a `ValueListenableBuilder`, instead of
/// calling `_TheaterScreenState.setState()` on every interaction, which
/// used to rebuild the entire screen — video included — on every single
/// `MouseRegion.onHover` tick while the mouse moved. `ValueNotifier`
/// already skips notifying listeners when a value is set to what it
/// already was, so repeatedly calling [registerActivity] while controls
/// are already visible (exactly what happens on every hover tick) costs a
/// cancelled+rescheduled `Timer`, not a rebuild.
class ControlsVisibilityController {
  final Player player;

  /// Read at hide-timer FIRE time, not captured once at schedule time —
  /// so a sub-menu that opens after the timer was armed still correctly
  /// suppresses the hide, matching the original inline behavior.
  final bool Function() isSubMenuOpen;

  ControlsVisibilityController({
    required this.player,
    required this.isSubMenuOpen,
  }) {
    _playingSub = player.stream.playing.listen(_onPlayingChanged);
  }

  static const Duration _hideDelay = Duration(seconds: 3);

  final ValueNotifier<bool> visible = ValueNotifier<bool>(true);

  Timer? _hideTimer;
  bool _interactionInProgress = false;
  late final StreamSubscription<bool> _playingSub;

  /// Call on any discrete interaction that should reveal the controls (if
  /// hidden) and restart the inactivity countdown.
  void registerActivity() {
    visible.value = true;
    _armTimer();
  }

  /// Call when a continuous interaction starts (a seekbar/volume drag).
  /// Suspends the hide timer until [endInteraction] is called.
  void beginInteraction() {
    _interactionInProgress = true;
    _hideTimer?.cancel();
    visible.value = true;
  }

  /// Call when that continuous interaction ends. Re-arms the countdown
  /// from a clean slate.
  void endInteraction() {
    _interactionInProgress = false;
    registerActivity();
  }

  /// Hides the controls immediately, bypassing the countdown — used for a
  /// direct "tap the background while controls are showing" gesture. Not
  /// gated on playback state: an explicit request to hide is honored even
  /// while paused, unlike the ambient auto-hide timer below, which never
  /// fires at all while paused.
  void hideNow() {
    _hideTimer?.cancel();
    visible.value = false;
  }

  void _onPlayingChanged(bool playing) {
    if (!playing) {
      // Paused — cancel any pending hide outright and force the controls
      // back on screen, rather than waiting for an already-scheduled timer
      // to fire and then no-op against the playing check below. Every UI
      // path in this codebase that pauses playback already calls
      // registerActivity()/onInteract() around the same time, so this is
      // primarily a defensive invariant — "controls are visible whenever
      // nothing is actively counting down to hide them" — rather than the
      // sole mechanism revealing them.
      _hideTimer?.cancel();
      visible.value = true;
    } else {
      _armTimer();
    }
  }

  void _armTimer() {
    _hideTimer?.cancel();
    if (_interactionInProgress) return;
    if (!player.state.playing) return;

    _hideTimer = Timer(_hideDelay, () {
      if (_interactionInProgress) return;
      if (!player.state.playing) return;
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
