import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../data/torrent/services/torrent_parser.dart';
import 'native_subtitle_parser.dart';
import 'streaming_controller_base.dart';

/// Streaming backend that delegates the torrent engine to the AniStream Go
/// server over LAN. See ARCHITECTURE.md § 5.
class RemoteStreamingController extends BaseStreamingController {
  final String serverUrl; // e.g. "http://192.168.1.5:7878"
  final http.Client _http;

  // State exposed to whichever theater screen owns this controller.
  String _statusText = 'Connecting to AniStream Server…';
  String? _streamUrl;
  bool _isReadyToPlay = false;
  bool _hasError = false;
  bool _needsManualSelection = false;
  List<BatchFileOption> _batchFiles = [];

  // Raw files from the last reparse; skips TorrentParser while unchanged.
  List<dynamic>? _lastRawFiles;

  String? _sessionId;
  Timer? _pollTimer;

  // Subtitles.
  bool _subtitlesAvailable = false;
  List<RemoteSubtitleTrack> _subtitleTracks = [];
  bool _fetchingSubtitleTracks = false;
  Timer? _subtitlePollTimer;
  // Whether each track's last fetch returned final content (absent: never).
  final Map<int, bool> _subtitleTrackComplete = {};

  // Consecutive failed polls (~5s at the 500ms interval) before erroring:
  // rides out a brief drop, but not a dead server.
  static const int _kMaxConsecutiveFailures = 10;
  int _consecutiveFailures = 0;

  RemoteStreamingController({required this.serverUrl}) : _http = http.Client();

  @override
  String get statusText => _statusText;
  @override
  String? get streamUrl => _streamUrl;
  @override
  bool get isReadyToPlay => _isReadyToPlay;
  @override
  bool get hasError => _hasError;
  @override
  bool get needsManualSelection => _needsManualSelection;
  @override
  List<BatchFileOption> get batchFiles => _batchFiles;
  @override
  bool get subtitlesAvailable => _subtitlesAvailable;
  @override
  List<RemoteSubtitleTrack> get subtitleTracks => _subtitleTracks;

  // Public API.

  @override
  Future<void> initialize(String magnetUri, {int? episodeNumber}) async {
    AppLogger.i(
      'StreamingController',
      'Adding magnet, requested episode: $episodeNumber',
    );
    try {
      final resp = await _http
          .post(
            Uri.parse('$serverUrl/api/stream'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'magnet': magnetUri,
              'episode_number': ?episodeNumber,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        _setError(_describeStreamError(resp));
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _sessionId = data['session_id'] as String?;

      if (_sessionId == null) {
        _setError('Server returned no session ID');
        return;
      }

      // Start polling for status updates.
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(_poll()),
      );
    } on TimeoutException {
      _setError('Server not reachable. Check the URL in Settings.');
    } catch (e) {
      _setError('Cannot connect to server: $e');
    }
  }

  /// The server's plain-text error body, or a generic HTTP-status message.
  String _describeStreamError(http.Response resp) {
    final body = resp.body.trim();
    if (body.isNotEmpty) return body;
    return 'Server returned HTTP ${resp.statusCode}. Is the URL correct?';
  }

  @override
  void selectBatchFile(int fileIndex) {
    if (_sessionId == null) return;

    // Dismiss the picker overlay immediately — the poll will update state.
    _needsManualSelection = false;
    notifyListeners();

    unawaited(
      _fireAndForget(
        _http
            .post(
              Uri.parse('$serverUrl/api/stream/$_sessionId/select'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'file_index': fileIndex}),
            )
            .timeout(const Duration(seconds: 10)),
      ),
    );

    // Re-arm the poll timer if it was somehow cancelled.
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_poll()),
    );
  }

  // Subtitles.

  @override
  Future<void> fetchSubtitleTracks() async {
    if (!_subtitlesAvailable ||
        _subtitleTracks.isNotEmpty ||
        _fetchingSubtitleTracks ||
        _sessionId == null) {
      return;
    }
    _fetchingSubtitleTracks = true;
    try {
      final resp = await _http
          .get(Uri.parse('$serverUrl/api/stream/$_sessionId/subtitles'))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawTracks = data['tracks'] as List<dynamic>? ?? [];
        _subtitleTracks = rawTracks
            .map((t) => RemoteSubtitleTrack.fromJson(t as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      AppLogger.w(
        'RemoteStreamingController',
        'Failed to fetch subtitle tracks: $e',
      );
      // Best-effort: tracks stay empty, so a later call retries.
    } finally {
      _fetchingSubtitleTracks = false;
    }
  }

  @override
  Future<String?> fetchSubtitleContent(int streamIndex) async {
    if (_sessionId == null) return null;
    try {
      final resp = await _http
          .get(
            Uri.parse(
              '$serverUrl/api/stream/$_sessionId/subtitles/$streamIndex',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return null;

      // x-subtitle-complete marks this response as final; tracked per track.
      final completeHeader = resp.headers['x-subtitle-complete'];
      _subtitleTrackComplete[streamIndex] = completeHeader == 'true';

      return resp.body;
    } catch (e) {
      AppLogger.w(
        'RemoteStreamingController',
        'Failed to fetch subtitle content for track $streamIndex: $e',
      );
      return null;
    }
  }

  /// Raw track bytes in [format] via the server's `?format=` param; shares
  /// [_subtitleTrackComplete] with [fetchSubtitleContent].
  @override
  Future<Uint8List?> fetchSubtitleBytes(
    int streamIndex,
    NativeSubtitleFormat format,
  ) async {
    if (_sessionId == null) return null;
    try {
      final resp = await _http
          .get(
            Uri.parse(
              '$serverUrl/api/stream/$_sessionId/subtitles/$streamIndex'
              '?format=${format.wireValue}',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return null;

      final completeHeader = resp.headers['x-subtitle-complete'];
      _subtitleTrackComplete[streamIndex] = completeHeader == 'true';

      return resp.bodyBytes;
    } catch (e) {
      AppLogger.w(
        'RemoteStreamingController',
        'Failed to fetch subtitle bytes for track $streamIndex ($format): $e',
      );
      return null;
    }
  }

  @override
  bool isSubtitleTrackComplete(int streamIndex) =>
      _subtitleTrackComplete[streamIndex] ?? false;

  /// Slow (5s), self-stopping poll for `subtitles_available`, which the server
  /// computes per request; the main poll stops at "ready" and can't watch it.
  void _startSubtitleAvailabilityPoll() {
    _subtitlePollTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_pollSubtitleAvailability()),
    );
  }

  Future<void> _pollSubtitleAvailability() async {
    if (_sessionId == null || _subtitlesAvailable) {
      _subtitlePollTimer?.cancel();
      _subtitlePollTimer = null;
      return;
    }
    try {
      final resp = await _http
          .get(Uri.parse('$serverUrl/api/stream/$_sessionId'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return; // transient — retry next tick

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final available = data['subtitles_available'] as bool? ?? false;
      if (available) {
        _subtitlesAvailable = true;
        _subtitlePollTimer?.cancel();
        _subtitlePollTimer = null;
        notifyListeners();
      }
    } catch (_) {
      // Transient — try again next tick.
    }
  }

  // Internal.

  /// Awaits [future] and discards any error, for best-effort calls.
  Future<void> _fireAndForget(Future<http.Response> future) async {
    try {
      await future;
    } catch (_) {
      // Best-effort — nothing to react to on failure.
    }
  }

  Future<void> _poll() async {
    if (_sessionId == null) return;

    try {
      final resp = await _http
          .get(Uri.parse('$serverUrl/api/stream/$_sessionId'))
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 404) {
        _setError('Session expired on server. Try restarting playback.');
        return;
      }
      if (resp.statusCode != 200) {
        _registerPollFailure();
        return;
      }

      _consecutiveFailures = 0;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final serverState = data['state'] as String? ?? 'error';

      // Snapshot first so notifyListeners() fires only on a real change, not
      // on every 500ms tick the picker is open.
      final prevStatusText = _statusText;
      final prevReady = _isReadyToPlay;
      final prevNeedsSelection = _needsManualSelection;
      final prevBatchFilesRef = _batchFiles;

      _statusText = data['status_text'] as String? ?? serverState;

      switch (serverState) {
        case 'loading_metadata':
          _isReadyToPlay = false;
          _needsManualSelection = false;

        case 'buffering':
          _isReadyToPlay = false;
          _needsManualSelection = false;

        case 'needs_selection':
          _needsManualSelection = true;
          final rawFiles = data['files'] as List<dynamic>? ?? [];

          if (!_sameRawFileList(rawFiles, _lastRawFiles)) {
            _lastRawFiles = rawFiles;
            _batchFiles = rawFiles.map((f) {
              final map = f as Map<String, dynamic>;
              final name = (map['name'] as String?) ?? '';
              final meta = TorrentParser.parse(name);
              return BatchFileOption(
                index: (map['index'] as num?)?.toInt() ?? 0,
                name: name,
                size: (map['size'] as num?)?.toInt() ?? 0,
                guessedEpisode: meta.episode == -1 ? null : meta.episode,
              );
            }).toList();
            AppLogger.i(
              'RemoteStreamingController',
              'Batch torrent detected — ${_batchFiles.length} files',
            );
          }
        // An unchanged list keeps the same _batchFiles reference, so the
        // identical() check below sees no change.

        case 'ready':
          final url = data['stream_url'] as String?;
          if (url != null && !_isReadyToPlay) {
            _streamUrl = url;
            _isReadyToPlay = true;
            // Stop polling — the stream URL won't change again.
            _pollTimer?.cancel();
            _pollTimer = null;
            if (!_subtitlesAvailable) {
              _startSubtitleAvailabilityPoll();
            }
          }

        case 'error':
          _setError(data['error'] as String? ?? 'Unknown server error');
          return;
      }

      final changed =
          _statusText != prevStatusText ||
          _isReadyToPlay != prevReady ||
          _needsManualSelection != prevNeedsSelection ||
          !identical(_batchFiles, prevBatchFilesRef);

      if (changed) {
        notifyListeners();
      }
    } on TimeoutException {
      // Counted toward _kMaxConsecutiveFailures.
      _registerPollFailure();
    } catch (_) {
      // Any other transient error — same treatment as a timeout.
      _registerPollFailure();
    }
  }

  /// Errors out after [_kMaxConsecutiveFailures] consecutive poll failures.
  void _registerPollFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _kMaxConsecutiveFailures) {
      _setError(
        "Lost connection to the AniStream Server. Check it's still "
        'running and reachable on your LAN, then try again.',
      );
    }
  }

  /// Cheap equality on the consumed fields (index/name/size), not a deep one.
  bool _sameRawFileList(List<dynamic> a, List<dynamic>? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final fa = a[i] as Map<String, dynamic>?;
      final fb = b[i] as Map<String, dynamic>?;
      if (fa == null || fb == null) return false;
      if (fa['index'] != fb['index'] ||
          fa['name'] != fb['name'] ||
          fa['size'] != fb['size']) {
        return false;
      }
    }
    return true;
  }

  void _setError(String msg) {
    _hasError = true;
    _statusText = msg;
    _pollTimer?.cancel();
    _pollTimer = null;
    _subtitlePollTimer?.cancel();
    _subtitlePollTimer = null;
    notifyListeners();
    AppLogger.e('RemoteStreamingController', msg);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _subtitlePollTimer?.cancel();
    if (_sessionId != null) {
      unawaited(
        _fireAndForget(
          _http
              .delete(Uri.parse('$serverUrl/api/stream/$_sessionId'))
              .timeout(const Duration(seconds: 5)),
        ),
      );
    }
    _http.close();
    super.dispose();
  }
}
