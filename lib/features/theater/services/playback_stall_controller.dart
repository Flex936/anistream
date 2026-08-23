import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Drives Theater's mid-playback "buffering" indicator off mpv's own
/// [Player.stream.buffering] signal — a single, backend-agnostic source
/// of truth for "is mpv currently blocked waiting on data," identical
/// whether the bytes are coming from `StreamingController`'s local
/// loopback server or `RemoteStreamingController`'s LAN connection to the
/// Go server. Neither `BaseStreamingController` implementation needs to
/// know this controller exists, and this controller never touches either
/// one — it only ever reads from [player].
///
/// [visible] is exposed the same way `ControlsVisibilityController.
/// visible` is — a `ValueNotifier<\bool>` `TheaterScreen` wraps in a
/// `ValueListenableBuilder`, so only the small indicator subtree rebuilds
/// on a show/hide transition rather than the whole screen.
class PlaybackStallController {
  final Player player;

  PlaybackStallController({required this.player}) {
    _playingSub = player.stream.playing.listen((_) => _reevaluate());
    _bufferingSub = player.stream.buffering.listen((_) => _reevaluate());
    _reevaluate();
  }

  /// How long mpv has to stay blocked on data before the indicator
  /// actually shows — filters out the brief blips a healthy stream sees
  /// routinely (a keyframe boundary, a momentary scheduling hiccup)
  /// rather than surfacing every one of them as "buffering." No matching
  /// delay on the hide side — once mpv reports caught up, the indicator
  /// clears immediately.
  static const Duration _kShowDelay = Duration(milliseconds: 500);

  /// How long after an interaction (a seekbar/volume drag) ends before
  /// stall detection re-arms. Seeking always triggers a real, expected
  /// buffering blip while mpv reloads at the new position — without this
  /// grace period, every deliberate scrub would flash the indicator for
  /// something the user did on purpose, not a genuine stall.
  static const Duration _kPostInteractionGrace = Duration(milliseconds: 800);

  final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;

  Timer? _showTimer;
  bool _suppressed = false;

  /// Call when a seekbar/volume drag starts — matches
  /// `ControlsVisibilityController`'s `beginInteraction`/`endInteraction`
  /// naming and bracket shape, and is meant to be called alongside it
  /// (see `TheaterScreen`'s combined interaction handlers).
  void beginInteraction() {
    _suppressed = true;
    _showTimer?.cancel();
    visible.value = false;
  }

  /// Call when that drag ends. Detection stays suppressed for
  /// [_kPostInteractionGrace] afterward rather than re-arming instantly,
  /// covering the buffering blip the resulting seek itself triggers.
  void endInteraction() {
    Timer(_kPostInteractionGrace, () {
      _suppressed = false;
      _reevaluate();
    });
  }

  void _reevaluate() {
    if (_suppressed) return;

    // `playing` reflects intent to play, not "am I currently rendering
    // frames" — mpv keeps this true through an underrun so it can resume
    // the instant data arrives. `buffering` is the actual engine-level
    // signal for "blocked waiting on data right now." Requiring both is
    // what keeps a deliberate pause (playing: false) from ever reading as
    // a stall.
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
      // Re-checks live state rather than trusting the state captured
      // when the timer was armed — mpv may have already recovered by
      // the time this fires.
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
