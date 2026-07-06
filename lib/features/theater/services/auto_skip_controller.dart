import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'theater_data.dart';

/// Owns the "auto-skip openings/endings" state machine. Feed it every
/// player position tick via [onPosition]; it seeks the player itself once
/// the 2s grace period elapses, and reports arming via [onSkipArmed] so the
/// UI can show a toast. Extracted out of `_TheaterScreenState`, which
/// previously held this logic inline as several loose fields.
class AutoSkipController {
  final Player player;
  final bool Function() isEnabled;
  final void Function(String skipLabel) onSkipArmed;

  AutoSkipController({
    required this.player,
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
          player.seek(active!.end);
          _isAutoSkipping = false;
        }
      });
    }
  }

  void dispose() => _timer?.cancel();
}
