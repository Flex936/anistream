import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'anilist_query_service.dart';
import 'package:anistream/core/logging/app_logger.dart';

class AnilistTrackerService {
  final AnilistQueryService _api = AnilistQueryService();
  bool _isLoggedIn = false;

  int? _mediaId;
  int? _currentEpisode;
  int? _totalEpisodes;

  bool _isEligible = false;
  bool _hasTracked = false;
  Timer? _delayTimer;
  final VoidCallback? onSuccess;

  AnilistTrackerService({this.onSuccess});

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
      final response = await _api.executeRaw(
        '''
        query (\$mediaId: Int) {
          Media(id: \$mediaId) { mediaListEntry { status progress } }
        }
      ''',
        {'mediaId': _mediaId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final listData = data['data']?['Media']?['mediaListEntry'];

        if (listData != null) {
          _status = listData['status'];
          _progress = listData['progress'] ?? 0;
        } else {
          _status = 'PLANNING';
          _progress = 0;
        }

        if (_currentEpisode != null) {
          if (_currentEpisode! > _progress || _status == 'PLANNING') {
            _isEligible = true;
          }
        }
      }
    } catch (e, st) {
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
      final response = await _api.executeRaw(
        '''
        mutation (\$mediaId: Int, \$progress: Int, \$status: MediaListStatus) {
          SaveMediaListEntry (mediaId: \$mediaId, progress: \$progress, status: \$status) { id }
        }
      ''',
        {'mediaId': _mediaId, 'progress': trackProgress, 'status': newStatus},
      );

      if (response.statusCode == 200) {
        onSuccess?.call();
      } else {
        _hasTracked = false;
      }
    } catch (e) {
      _hasTracked = false;
    }
  }

  void dispose() {
    _delayTimer?.cancel();
  }
}
