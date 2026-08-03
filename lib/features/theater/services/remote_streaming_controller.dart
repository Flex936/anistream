import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
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
///
/// Subtitles (added)
/// ──────────────────
/// A separate, slower poll starts once step 3 completes, checking
/// subtitles_available independently — that flag needs the WHOLE file
/// downloaded (not just the 5% buffer threshold that unlocks playback),
/// so it can flip true well after the main poll loop above has already
/// stopped for good reason (stream_url never changes again). See
/// _startSubtitleAvailabilityPoll.
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

  // ── Cache of the raw (undecoded-to-BatchFileOption) file list from the
  // last poll where we actually reparsed it. While the batch picker is open,
  // the server returns the exact same file list every single 500ms tick —
  // reparsing every filename via TorrentParser.parse() on every poll was
  // real, repeated, avoidable CPU work on the UI isolate for as long as the
  // user sat looking at the picker. Only reparse (and rebuild _batchFiles)
  // when the server's list has actually changed. ──
  List<dynamic>? _lastRawFiles;

  String? _sessionId;
  Timer? _pollTimer;

  // ── Subtitles (added) ──────────────────────────────────────────────────
  bool _subtitlesAvailable = false;
  List<RemoteSubtitleTrack> _subtitleTracks = [];
  bool _fetchingSubtitleTracks = false;
  Timer? _subtitlePollTimer;

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

  // ── Public API ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(String magnetUri, {int? episodeNumber}) async {
    AppLogger.i(
      'StreamingController',
      'Adding magnet, requested episode: $episodeNumber',
    );
    AppLogger.i(
      'StreamingController',
      'Batch torrent detected — ${_batchFiles.length} files',
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
        (_) => unawaited(_poll()),
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

    // ── _fireAndForget (see below) instead of a chained .catchError(). A
    // bare `.catchError((_) {})` on a Future<http.Response> requires the
    // callback to return something assignable to `Response` (or a Future
    // of one) — an empty body implicitly returns null, which the analyzer
    // correctly rejects (body_might_complete_normally_catch_error).
    // Wrapping in a try/catch inside a Future<void> helper sidesteps the
    // typing requirement while keeping identical "best-effort, ignore
    // failures" behavior. The outer `unawaited()` is needed too —
    // `_fireAndForget` itself returns a `Future<void>`, so calling it from
    // this (necessarily synchronous) method is itself a discarded future
    // under `unawaited_futures`. ──
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

  // ── Subtitles (added) ─────────────────────────────────────────────────────

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
            .map(
              (t) => RemoteSubtitleTrack.fromJson(t as Map<String, dynamic>),
            )
            .toList();
        notifyListeners();
      }
    } catch (e) {
      AppLogger.w(
        'RemoteStreamingController',
        'Failed to fetch subtitle tracks: $e',
      );
      // Best-effort — leave _subtitleTracks empty; the caller (the
      // theater screen) can call fetchSubtitleTracks() again later,
      // since the guard above only skips while tracks are still empty.
    } finally {
      _fetchingSubtitleTracks = false;
    }
  }

  @override
  String? subtitleUrlFor(int streamIndex) {
    if (_sessionId == null) return null;
    return '$serverUrl/api/stream/$_sessionId/subtitles/$streamIndex';
  }

  /// Starts a slow (5s), self-stopping poll purely for subtitles_available.
  /// Deliberately separate from the main 500ms _pollTimer above, which
  /// intentionally stops once state first reaches "ready" — stream_url
  /// never changes after that, so there's nothing left for it to watch.
  /// subtitles_available is different: the server can't confirm it until
  /// the WHOLE file has downloaded, which routinely happens well after
  /// playback has already started off the 5% buffer threshold. Idempotent
  /// — safe to call more than once, only ever arms one timer.
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

  // ── Internal ──────────────────────────────────────────────────────────────

  /// Awaits [future] and silently discards any error. Used for best-effort
  /// network calls (batch-file selection, session teardown) where the
  /// caller has already moved on regardless of the outcome.
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
      if (resp.statusCode != 200) return; // transient error, keep polling

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final serverState = data['state'] as String? ?? 'error';

      // ── Snapshot every field this controller exposes BEFORE mutating,
      // so we can tell at the end whether anything actually changed.
      // Without this, notifyListeners() fired unconditionally on every
      // 500ms tick — including the entire time the batch picker sat open
      // with nothing new to show — rebuilding BatchEpisodePickerOverlay's
      // ListView.builder for no reason. ──
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
            // ── `rawFiles` is `List<dynamic>`, so each element `f` is
            // `dynamic` until cast — indexing straight into `f['name']`
            // would be an index operation on a dynamic receiver
            // (avoid_dynamic_calls). Casting once up front keeps every
            // field access below statically typed. ──
            _batchFiles = rawFiles.map((f) {
              final map = f as Map<String, dynamic>;
              final name = (map['name'] as String?) ?? '';
              // Reuse the existing Dart parser to guess the episode number
              // from the filename — no duplication of logic on the server.
              final meta = TorrentParser.parse(name);
              return BatchFileOption(
                index: (map['index'] as num?)?.toInt() ?? 0,
                name: name,
                size: (map['size'] as num?)?.toInt() ?? 0,
                guessedEpisode: meta.episode == -1 ? null : meta.episode,
              );
            }).toList();
          }
        // else: server sent the exact same list — _batchFiles is left
        // untouched (same reference), which also lets the change-check
        // below correctly see "no change" via identical().

        case 'ready':
          final url = data['stream_url'] as String?;
          if (url != null && !_isReadyToPlay) {
            _streamUrl = url;
            _isReadyToPlay = true;
            // Stop polling — the stream URL won't change again.
            _pollTimer?.cancel();
            _pollTimer = null;
            // ── Subtitles (added): subtitles_available can still flip
            // true much later than this — it needs the whole file, not
            // just the 5% buffer threshold that got us here. Handed off
            // to its own slower, self-stopping poll rather than keeping
            // this 500ms loop alive for a value that's usually still
            // false at exactly this moment. ──
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
      // Network hiccup — silently retry on the next tick.
    } catch (_) {
      // Any other transient error — keep polling.
    }
  }

  /// Cheap content-equality check between two raw (still-JSON, not yet
  /// parsed into [BatchFileOption]) file lists from consecutive polls.
  /// Compares only the fields we actually consume (`index`/`name`/`size`),
  /// which is enough to tell "the server sent the identical list again"
  /// from "something actually changed" without needing a full deep-equals.
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
      // Best-effort cleanup; don't let errors bubble up during disposal.
      // See _fireAndForget's doc comment for why this isn't a chained
      // .catchError() anymore, and unawaited()'s doc comment above in
      // selectBatchFile for why the outer call needs wrapping too.
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