import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/torrent/services/torrent_parser.dart';
import 'streaming_controller_base.dart';

/// Connects to the AniStream Go server instead of running libtorrent locally.
///
/// Usage is identical to [StreamingController] — [TheaterScreen] receives this
/// as a [BaseStreamingController] and never touches server-specific details.
///
/// Flow
/// ────
///  1. [initialize] POSTs the magnet link to the server → gets a session ID.
///  2. A 500 ms poll timer calls GET /api/stream/:id and maps the JSON state
///     to the same bool flags that [StreamingController] exposes.
///  3. When the server reports "ready", [streamUrl] is set to the server's
///     /video endpoint. MPV opens that URL directly; all range requests
///     (seeking) are handled server-side via http.ServeContent.
///  4. On dispose, DELETE /api/stream/:id frees server resources.
class RemoteStreamingController extends BaseStreamingController {
  final String serverUrl; // e.g. "http://192.168.1.5:7878"
  final http.Client _http;

  // ── State exposed to TheaterScreen ──
  String _statusText = 'Connecting to AniStream Server…';
  String? _streamUrl;
  bool _isReadyToPlay = false;
  bool _hasError = false;
  bool _needsManualSelection = false;
  List<BatchFileOption> _batchFiles = [];

  String? _sessionId;
  Timer? _pollTimer;

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

  // ── Public API ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(String magnetUri, {int? episodeNumber}) async {
    try {
      final resp = await _http
          .post(
            Uri.parse('$serverUrl/api/stream'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'magnet': magnetUri,
              if (episodeNumber != null) 'episode_number': episodeNumber,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        _setError(
          'Server returned HTTP ${resp.statusCode}. Is the URL correct?',
        );
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
        (_) => _poll(),
      );
    } on TimeoutException {
      _setError('Server not reachable. Check the URL in Settings.');
    } catch (e) {
      _setError('Cannot connect to server: $e');
    }
  }

  @override
  void selectBatchFile(int fileIndex) {
    if (_sessionId == null) return;

    // Dismiss the picker overlay immediately — the poll will update state.
    _needsManualSelection = false;
    notifyListeners();

    _http
        .post(
          Uri.parse('$serverUrl/api/stream/$_sessionId/select'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'file_index': fileIndex}),
        )
        .timeout(const Duration(seconds: 10))
        .catchError((_) {});

    // Re-arm the poll timer if it was somehow cancelled.
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _poll(),
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────────

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
      if (resp.statusCode != 200) return; // transient error, keep polling

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final serverState = data['state'] as String? ?? 'error';

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
          _batchFiles = rawFiles.map((f) {
            final name = (f['name'] as String?) ?? '';
            // Reuse the existing Dart parser to guess the episode number
            // from the filename — no duplication of logic on the server.
            final meta = TorrentParser.parse(name);
            return BatchFileOption(
              index: (f['index'] as num?)?.toInt() ?? 0,
              name: name,
              size: (f['size'] as num?)?.toInt() ?? 0,
              guessedEpisode: meta.episode == -1 ? null : meta.episode,
            );
          }).toList();

        case 'ready':
          final url = data['stream_url'] as String?;
          if (url != null && !_isReadyToPlay) {
            _streamUrl = url;
            _isReadyToPlay = true;
            // Stop polling — the stream URL won't change again.
            _pollTimer?.cancel();
            _pollTimer = null;
          }

        case 'error':
          _setError(data['error'] as String? ?? 'Unknown server error');
          return;
      }

      notifyListeners();
    } on TimeoutException {
      // Network hiccup — silently retry on the next tick.
    } catch (_) {
      // Any other transient error — keep polling.
    }
  }

  void _setError(String msg) {
    _hasError = true;
    _statusText = msg;
    _pollTimer?.cancel();
    _pollTimer = null;
    notifyListeners();
    debugPrint('[RemoteStreamingController] Error: $msg');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_sessionId != null) {
      // Best-effort cleanup; don't let errors bubble up during disposal.
      _http
          .delete(Uri.parse('$serverUrl/api/stream/$_sessionId'))
          .timeout(const Duration(seconds: 5))
          .catchError((_) {});
    }
    _http.close();
    super.dispose();
  }
}
