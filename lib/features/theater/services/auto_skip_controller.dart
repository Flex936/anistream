import 'dart:async';
import 'theater_data.dart';

/// Auto-skip state machine shared by both theater screens: feed it position
/// ticks via [onPosition]; it seeks after a 2s grace and reports arming via
/// [onSkipArmed].
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
          unawaited(onSeek(active!.end));
          _isAutoSkipping = false;
        }
      });
    }
  }

  void dispose() => _timer?.cancel();
}
