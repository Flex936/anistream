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

  /// Called with a short, user-facing message on a failed commit attempt — the
  /// request itself failed, or AniList returned HTTP 200 with a GraphQL
  /// `errors` array (an expired token, a validation failure) a bare status
  /// check can't catch.
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
        // A genuinely missing entry means this anime isn't on the viewer's list
        // yet — distinct from the catch block below, where the lookup itself
        // failed rather than confirming "nothing found."
        _status = 'PLANNING';
        _progress = 0;
      }

      if (_currentEpisode != null) {
        if (_currentEpisode! > _progress || _status == 'PLANNING') {
          _isEligible = true;
        }
      }
    } catch (e, st) {
      // A failed lookup leaves `_isEligible` false rather than falling into the
      // PLANNING/0 branch above — treating a network error as "never watched"
      // could wrongly arm tracking for someone already partway through, or let
      // a later commit overwrite real progress. Tracking simply doesn't arm
      // this session; the next episode's `TheaterScreen` retries fresh.
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
      // Reset so the next qualifying position tick re-arms a fresh timer and
      // retries — a transient failure here shouldn't permanently disable
      // tracking for the episode.
      _hasTracked = false;
      onFailure?.call('Could not save progress to AniList');
      AppLogger.e('AnilistTrackerService', 'Commit progress error', e, st);
    }
  }

  void dispose() {
    _delayTimer?.cancel();
  }

  /// Fires an armed-but-uncommitted sync immediately on any exit path, bounded
  /// to [_kFlushTimeout] — see API.md § 2 for why the bound exists and why the
  /// request keeps running in the background rather than being cancelled.
  Future<void> flushPendingCommit() async {
    if (_delayTimer == null || !_delayTimer!.isActive) return;
    _delayTimer!.cancel();
    await _commitToAnilist().timeout(_kFlushTimeout, onTimeout: () {});
  }
}