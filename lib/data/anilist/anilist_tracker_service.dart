import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import 'anilist_queries.dart';
import 'anilist_query_service.dart';

/// Watches playback position against the 90%-watched threshold and syncs
/// progress to AniList once eligible. See API.md § 2 (Auto-tracking) for
/// the documented threshold/eligibility rules this class implements.
class AnilistTrackerService {
  final AnilistQueryService _api = AnilistQueryService();
  bool _isLoggedIn = false;

  int? _mediaId;
  int? _currentEpisode;
  int? _totalEpisodes;

  bool _isEligible = false;
  bool _hasTracked = false;
  Timer? _delayTimer;

  /// Upper bound on how long [flushPendingCommit] will wait for the
  /// underlying request — see that method's doc comment for why this is
  /// bounded at all.
  static const Duration _kFlushTimeout = Duration(seconds: 3);

  final VoidCallback? onSuccess;

  /// Called with a short, user-facing message whenever a commit attempt
  /// fails — either the request itself failed, or AniList accepted it
  /// but returned a GraphQL-level `errors` array (an expired token
  /// mid-session, a validation failure), which a bare HTTP-200 check
  /// can't distinguish from a genuine success.
  final void Function(String message)? onFailure;

  AnilistTrackerService({this.onSuccess, this.onFailure});

  Future<void> init({
    required int mediaId,
    required int episode,
    int? totalEpisodes,
  }) async {
    try {
      if (!AnilistQueryService.isLoggedIn) {
        _isLoggedIn = false;
        return;
      }
      _isLoggedIn = true;
      _mediaId = mediaId;
      _currentEpisode = episode;
      _totalEpisodes = totalEpisodes;

      await _fetchCurrentStatus();
    } catch (e, st) {
      AppLogger.e('AnilistTrackerService', 'Fetch status error', e, st);
    }
  }

  String? _status;
  int _progress = 0;

  Future<void> _fetchCurrentStatus() async {
    try {
      final data = await _api.executeChecked(
        AnilistQueries.mediaListEntryStatus,
        {'mediaId': _mediaId},
      );
      final media = data['Media'] as Map<String, dynamic>?;
      final listData = media?['mediaListEntry'] as Map<String, dynamic>?;

      if (listData != null) {
        _status = listData['status'] as String?;
        _progress = (listData['progress'] as num?)?.toInt() ?? 0;
      } else {
        // A genuinely missing entry — this anime isn't on the viewer's
        // list yet. Distinct from the catch block below, which means the
        // lookup itself failed rather than confirming "nothing found".
        _status = 'PLANNING';
        _progress = 0;
      }

      if (_currentEpisode != null) {
        if (_currentEpisode! > _progress || _status == 'PLANNING') {
          _isEligible = true;
        }
      }
    } catch (e, st) {
      // A failed lookup leaves _isEligible at its default (false) rather
      // than falling into the PLANNING/0 branch above — treating a
      // network or GraphQL error as "never watched" could wrongly arm
      // tracking for someone already partway through, or let a later
      // commit overwrite real progress with a guessed status. Tracking
      // simply doesn't arm for this session; the next episode's
      // TheaterScreen instance tries the lookup again fresh.
      AppLogger.e('AnilistTrackerService', 'Fetch status error', e, st);
    }
  }

  void updateProgress(Duration position, Duration duration) {
    if (!_isLoggedIn ||
        !_isEligible ||
        _hasTracked ||
        duration.inMilliseconds == 0) {
      return;
    }

    final percent = position.inMilliseconds / duration.inMilliseconds;

    if (percent >= 0.90) {
      if (_delayTimer == null || !_delayTimer!.isActive) {
        _delayTimer = Timer(const Duration(seconds: 5), _commitToAnilist);
      }
    } else {
      if (_delayTimer != null && _delayTimer!.isActive) {
        _delayTimer!.cancel();
      }
    }
  }

  Future<void> _commitToAnilist() async {
    if (_hasTracked) return;
    _hasTracked = true;

    String newStatus = _status ?? 'CURRENT';
    final int trackProgress =
        (_currentEpisode != null && _currentEpisode! > _progress)
        ? _currentEpisode!
        : _progress;

    if (_status == 'PLANNING') newStatus = 'CURRENT';
    if (_totalEpisodes != null &&
        _totalEpisodes! > 0 &&
        trackProgress == _totalEpisodes) {
      newStatus = 'COMPLETED';
    }

    try {
      await _api.executeChecked(AnilistQueries.saveMediaListEntry, {
        'mediaId': _mediaId,
        'progress': trackProgress,
        'status': newStatus,
      });
      onSuccess?.call();
    } catch (e, st) {
      // Reset so the next qualifying position tick re-arms a fresh
      // 5-second timer and tries again — a transient failure here
      // shouldn't permanently disable tracking for the rest of the
      // episode.
      _hasTracked = false;
      onFailure?.call('Could not save progress to AniList');
      AppLogger.e('AnilistTrackerService', 'Commit progress error', e, st);
    }
  }

  void dispose() {
    _delayTimer?.cancel();
  }

  /// Immediately attempts a commit if one is currently armed
  /// (`_delayTimer` active) but hasn't fired yet — call this before
  /// [dispose] on any exit path, so backing out right after crossing the
  /// 90% threshold doesn't silently drop that episode's sync the way
  /// letting [dispose] cancel the timer outright would.
  ///
  /// Bounded to [_kFlushTimeout] rather than left to the request's normal
  /// completion time: unlike a commit armed mid-playback (which can just
  /// retry on the next qualifying position tick if it fails), there's no
  /// "next tick" once the screen is closing, so this can't be allowed to
  /// block an exit indefinitely on a slow or hung connection. The
  /// underlying request isn't cancelled on timeout — Dart futures can't
  /// be cancelled — it's left to complete in the background and still
  /// calls [onSuccess]/[onFailure] if it resolves after this method has
  /// already returned; this only stops waiting on it.
  Future<void> flushPendingCommit() async {
    if (_delayTimer == null || !_delayTimer!.isActive) return;
    _delayTimer!.cancel();
    await _commitToAnilist().timeout(_kFlushTimeout, onTimeout: () {});
  }
}
