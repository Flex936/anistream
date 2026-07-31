import 'dart:async';
import 'theater_data.dart';

/// Owns the "auto-skip openings/endings" state machine. Feed it every
/// player position tick via [onPosition]; it seeks via [onSeek] itself
/// once the 2s grace period elapses, and reports arming via [onSkipArmed]
/// so the UI can show a toast.
///
/// Deliberately decoupled from any specific player type — [onSeek] is
/// just `Future<void> Function(Duration)`, so
/// `AutoSkipController(onSeek: _player.seek, ...)` works unchanged
/// whether `_player` is media_kit's `Player` or any other engine's
/// controller with a `seek(Duration)` method. Previously took a
/// media_kit `Player` directly and called `player.seek(...)` itself,
/// which meant a second, otherwise-identical copy of this entire state
/// machine would have been needed for every additional player engine —
/// only the one-line call site differs now, not the class.
class AutoSkipController {
  final Future<void> Function(Duration position) onSeek;
  final bool Function() isEnabled;
  final void Function(String skipLabel) onSkipArmed;

  AutoSkipController({
    required this.onSeek,
    required this.isEnabled,
    required this.onSkipArmed,
  });

  List<Chapter> chapters = [];
  bool _isAutoSkipping = false;
  Chapter? _currentChapter;
  Timer? _timer;

  void onPosition(Duration pos) {
    if (!isEnabled() || chapters.isEmpty) return;

    Chapter? active;
    for (final c in chapters) {
      if (c.isSkippable &&
          pos >= c.start &&
          pos < (c.end - const Duration(seconds: 1))) {
        active = c;
        break;
      }
    }

    if (active == null) {
      if (_isAutoSkipping) {
        _timer?.cancel();
        _isAutoSkipping = false;
        _currentChapter = null;
      }
      return;
    }

    if (_currentChapter != active) {
      _timer?.cancel();
      _isAutoSkipping = true;
      _currentChapter = active;
      onSkipArmed(active.skipLabel ?? 'Skip');

      _timer = Timer(const Duration(seconds: 2), () {
        if (_isAutoSkipping && _currentChapter == active) {
          // ── Timer callbacks are synchronous — onSeek returns a
          // Future<void> that can't be awaited here, so the
          // fire-and-forget intent is made explicit instead of silently
          // dropped (unawaited_futures). ──
          unawaited(onSeek(active!.end));
          _isAutoSkipping = false;
        }
      });
    }
  }

  void dispose() => _timer?.cancel();
}