import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Drives Theater's buffering indicator from mpv's [Player.stream.buffering],
/// so it works for either streaming backend and never touches them.
class PlaybackStallController {
  final Player player;

  PlaybackStallController({required this.player}) {
    _playingSub = player.stream.playing.listen((_) => _reevaluate());
    _bufferingSub = player.stream.buffering.listen((_) => _reevaluate());
    _reevaluate();
  }

  /// How long mpv must stay blocked before the indicator shows, filtering
  /// routine blips; hiding is immediate.
  static const Duration _kShowDelay = Duration(milliseconds: 500);

  /// Suppression after a drag ends, covering the seek's own buffering blip.
  static const Duration _kPostInteractionGrace = Duration(milliseconds: 800);

  final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;

  Timer? _showTimer;
  bool _suppressed = false;

  /// Call when a seekbar/volume drag starts, alongside
  /// `ControlsVisibilityController.beginInteraction`.
  void beginInteraction() {
    _suppressed = true;
    _showTimer?.cancel();
    visible.value = false;
  }

  /// Call when the drag ends; detection re-arms after [_kPostInteractionGrace].
  void endInteraction() {
    Timer(_kPostInteractionGrace, () {
      _suppressed = false;
      _reevaluate();
    });
  }

  void _reevaluate() {
    if (_suppressed) return;

    // `playing` is intent, not rendering: mpv keeps it true through an
    // underrun. Requiring `buffering` keeps a pause from reading as a stall.
    final isStalled = player.state.playing && player.state.buffering;

    if (!isStalled) {
      _showTimer?.cancel();
      _showTimer = null;
      visible.value = false;
      return;
    }

    // Already counting down or already shown — nothing new to do.
    if (visible.value || _showTimer != null) return;

    _showTimer = Timer(_kShowDelay, () {
      _showTimer = null;
      // Re-check live state; mpv may have recovered since arming.
      if (!_suppressed && player.state.playing && player.state.buffering) {
        visible.value = true;
      }
    });
  }

  void dispose() {
    _showTimer?.cancel();
    unawaited(_playingSub.cancel());
    unawaited(_bufferingSub.cancel());
    visible.dispose();
  }
}
