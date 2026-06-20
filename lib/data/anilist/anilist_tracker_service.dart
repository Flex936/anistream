import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_auth_service.dart';

class AnilistTrackerService {
  final AnilistAuthService _auth = AnilistAuthService();
  bool _isLoggedIn = false;
  String? _token;

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
      _token = await _auth.getStoredToken();
      if (_token == null || _token!.isEmpty) {
        _isLoggedIn = false;
        return;
      }
      _isLoggedIn = true;
      _mediaId = mediaId;
      _currentEpisode = episode;
      _totalEpisodes = totalEpisodes;

      await _fetchCurrentStatus();
    } catch (e) {
      debugPrint('[AnilistTracker] Init error: $e');
    }
  }

  String? _status;
  int _progress = 0;

  Future<void> _fetchCurrentStatus() async {
    try {
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': '''
            query (\$mediaId: Int) {
              Media(id: \$mediaId) {
                mediaListEntry {
                  status
                  progress
                }
              }
            }
          ''',
          'variables': {'mediaId': _mediaId},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Correctly fetch the authenticated user's specific list entry
        final listData = data['data']?['Media']?['mediaListEntry'];

        if (listData != null) {
          _status = listData['status'];
          _progress = listData['progress'] ?? 0;
        } else {
          _status = 'PLANNING';
          _progress = 0;
        }

        // Safeguard: Track if the episode we are watching is > the saved progress
        // OR if the status is currently PLANNING (so we can promote it to CURRENT)
        if (_currentEpisode != null) {
          if (_currentEpisode! > _progress || _status == 'PLANNING') {
            _isEligible = true;
            debugPrint(
              '[AnilistTracker] Eligible to track. Current progress: $_progress. Watching: $_currentEpisode. Status: $_status',
            );
          } else {
            debugPrint(
              '[AnilistTracker] Ineligible. Already watched episode $_currentEpisode or further.',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[AnilistTracker] Fetch status error: $e');
    }
  }

  void updateProgress(Duration position, Duration duration) {
    if (!_isLoggedIn || !_isEligible || _hasTracked) return;
    if (duration.inMilliseconds == 0) return;

    final percent = position.inMilliseconds / duration.inMilliseconds;

    // Start tracking if at >= 90%
    if (percent >= 0.90) {
      if (_delayTimer == null || !_delayTimer!.isActive) {
        debugPrint('[AnilistTracker] Reached 90%. Starting 5s timer...');
        _delayTimer = Timer(const Duration(seconds: 5), _commitToAnilist);
      }
    } else {
      // Safeguard: If the user seeks back before 5 seconds, cancel the timer
      if (_delayTimer != null && _delayTimer!.isActive) {
        debugPrint('[AnilistTracker] User seeked back. Canceling track timer.');
        _delayTimer!.cancel();
      }
    }
  }

  Future<void> _commitToAnilist() async {
    if (_hasTracked) return;
    _hasTracked = true; // Block multiple fires instantly

    String newStatus = _status ?? 'CURRENT';

    // Prevent downgrading progress if we are just promoting a PLANNING anime to CURRENT
    final int trackProgress =
        (_currentEpisode != null && _currentEpisode! > _progress)
        ? _currentEpisode!
        : _progress;

    // Status Logic Routing
    if (_status == 'PLANNING') {
      newStatus = 'CURRENT';
    }
    if (_totalEpisodes != null &&
        _totalEpisodes! > 0 &&
        trackProgress == _totalEpisodes) {
      newStatus = 'COMPLETED';
    }

    try {
      debugPrint(
        '[AnilistTracker] Committing to AniList: EP $trackProgress, Status: $newStatus',
      );
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': '''
            mutation (\$mediaId: Int, \$progress: Int, \$status: MediaListStatus) {
              SaveMediaListEntry (mediaId: \$mediaId, progress: \$progress, status: \$status) {
                id
              }
            }
          ''',
          'variables': {
            'mediaId': _mediaId,
            'progress': trackProgress,
            'status': newStatus,
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[AnilistTracker] Successfully saved to AniList!');
        onSuccess?.call();
      } else {
        debugPrint(
          '[AnilistTracker] Save failed with code ${response.statusCode}: ${response.body}',
        );
        _hasTracked = false; // Allow retry on transient network errors
      }
    } catch (e) {
      debugPrint('[AnilistTracker] Commit error: $e');
      _hasTracked = false;
    }
  }

  void dispose() {
    _delayTimer?.cancel();
  }
}
