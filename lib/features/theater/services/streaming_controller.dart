import 'dart:async';

import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/torrent/services/torrent_parser.dart';
import 'streaming_controller_base.dart';

export 'streaming_controller_base.dart' show BatchFileOption;

class StreamingController extends BaseStreamingController {
  // Minimum sequential buffer percentage before the URL is handed to the
  // player. 2% gives MPV a solid head-start without making the user wait
  // long. Raise it if black-frames persist on very slow connections.
  static const double _kPreBufferThreshold = 0.1;

  String _statusText = 'Initializing Native Engine...';
  @override
  String get statusText => _statusText;

  String? _streamUrl;
  @override
  String? get streamUrl => _streamUrl;

  bool _isReadyToPlay = false;
  @override
  bool get isReadyToPlay => _isReadyToPlay;

  bool _hasError = false;
  @override
  bool get hasError => _hasError;

  int? _torrentId;
  StreamSubscription<Map<int, TorrentInfo>>? _torrentSub;
  StreamSubscription<dynamic>? _streamSub;

  bool _needsManualSelection = false;
  @override
  bool get needsManualSelection => _needsManualSelection;

  List<BatchFileOption> _batchFiles = [];
  @override
  List<BatchFileOption> get batchFiles => _batchFiles;

  int? _requestedEpisode;
  bool _filesResolved = false;

  // Guards the window between a batch-file selection being requested and
  // its stream actually reaching `_isReadyToPlay` — `selectBatchFile`'s
  // existing `_isReadyToPlay` check only closes the window *after* that
  // point, not during it, so a stray repeat tap (D-pad double-fire, a
  // second pointer event) in between could otherwise call `_beginStream`
  // twice and leave the first call's local stream/subscription orphaned.
  bool _isMountingStream = false;

  // Ceiling on each phase of reaching `_isReadyToPlay` — started in
  // `initialize()` to cover metadata resolution (no peers hold this info
  // hash), then restarted fresh in `_beginStream` to cover the buffering
  // phase separately (a dried-up swarm after file selection), so time
  // spent on the batch picker in between never eats into the buffering
  // budget. Matches the companion Go server's own documented 3-minute
  // metadata timeout (ARCHITECTURE.md § 6) so an on-device session fails
  // out on a comparable timescale instead of spinning on the loading
  // overlay forever with no path to `_hasError`.
  static const Duration _kStreamTimeout = Duration(minutes: 3);
  Timer? _streamTimeoutTimer;

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
    _requestedEpisode = episodeNumber;
    try {
      await LibtorrentFlutter.init();
      final engine = LibtorrentFlutter.instance;

      _torrentSub = engine.torrentUpdates.listen(
        (torrents) => _handleTorrentUpdate(engine, torrents),
        onError: (Object e) => _handleError('Engine sync failed: $e'),
      );

      _torrentId = engine.addMagnet(magnetUri);
      _streamTimeoutTimer = Timer(_kStreamTimeout, _handleStreamTimeout);
    } catch (e) {
      _handleError('Failed to initialize engine: $e');
    }
  }

  void _handleTorrentUpdate(
    LibtorrentFlutter engine,
    Map<int, TorrentInfo> torrents,
  ) {
    if (_torrentId == null || !torrents.containsKey(_torrentId)) {
      return;
    }

    final t = torrents[_torrentId]!;

    if (!t.hasMetadata) {
      _updateStatus('Fetching metadata... (Peers: ${t.numPeers})');
      return;
    }

    if (!_filesResolved) {
      _filesResolved = true;
      _resolveFilesAndStartStream(engine);
    }
  }

  void _resolveFilesAndStartStream(LibtorrentFlutter engine) {
    _updateStatus('Reading file list...');

    try {
      final files = engine.getFiles(_torrentId!);
      final videoFiles = files.where((f) => f.isStreamable).toList();

      if (videoFiles.length <= 1) {
        _beginStream(
          engine,
          fileIndex: videoFiles.isEmpty ? null : videoFiles.first.index,
        );
        return;
      }

      // Batch torrent: multiple episodes packed into one torrent.
      _batchFiles =
          videoFiles
              .map(
                (f) => BatchFileOption(
                  index: f.index,
                  name: f.name,
                  size: f.size,
                  guessedEpisode: _guessEpisodeNumber(f.name),
                ),
              )
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));

      if (_requestedEpisode != null) {
        final matches = _batchFiles
            .where((f) => f.guessedEpisode == _requestedEpisode)
            .toList();

        if (matches.length == 1) {
          _updateStatus(
            'Found Episode $_requestedEpisode in batch, starting...',
          );
          _beginStream(engine, fileIndex: matches.first.index);
          return;
        }
      }

      _needsManualSelection = true;
      _updateStatus('Batch torrent detected — choose an episode');
      notifyListeners();
    } catch (e) {
      _handleError('Failed to resolve files: $e');
    }
  }

  @override
  void selectBatchFile(int fileIndex) {
    AppLogger.i(
      'StreamingController',
      'Batch torrent detected — ${_batchFiles.length} files',
    );
    if (_torrentId == null || _isReadyToPlay || _isMountingStream) return;

    _isMountingStream = true;
    _needsManualSelection = false;
    _statusText = 'Initializing selected file…';
    notifyListeners();
    _beginStream(LibtorrentFlutter.instance, fileIndex: fileIndex);
  }

  void _beginStream(LibtorrentFlutter engine, {int? fileIndex}) {
    // Restarts the ceiling fresh for the buffering phase. The timer
    // `initialize()` started only needs to cover metadata resolution —
    // for a batch torrent, the user may spend any amount of time
    // browsing BatchEpisodePickerOverlay before selecting a file, and
    // that decision time shouldn't eat into the budget the swarm gets to
    // actually deliver sequential bytes afterward.
    _streamTimeoutTimer?.cancel();
    _streamTimeoutTimer = Timer(_kStreamTimeout, _handleStreamTimeout);

    // Tears down any previous subscription before mounting a new one —
    // defensive even though `_isMountingStream`/`_isReadyToPlay` above
    // already keep `selectBatchFile` from re-entering this method while
    // one mount is in flight, since `_beginStream` also has the
    // auto-resolved single-file call path in `_resolveFilesAndStartStream`.
    unawaited(_streamSub?.cancel() ?? Future<void>.value());

    try {
      final streamInfo = fileIndex == null
          ? engine.startStream(_torrentId!)
          : engine.startStream(_torrentId!, fileIndex: fileIndex);

      _streamUrl = streamInfo.url;
      _updateStatus('Buffering… 0.0%');

      _streamSub = engine.streamUpdates.listen((streams) {
        if (_hasError) return;

        try {
          final s = streams.values.firstWhere((st) => st.url == _streamUrl);
          final pct = s.bufferPct;

          if (_isReadyToPlay) {
            AppLogger.i(
              'Torrent',
              'Sequential Buffer: ${pct.toStringAsFixed(1)}%',
            );
            return;
          }

          final label = 'Buffering… ${pct.toStringAsFixed(1)}%';
          if (_statusText != label) {
            _statusText = label;
            notifyListeners();
          }

          if (pct >= _kPreBufferThreshold) {
            _isReadyToPlay = true;
            _isMountingStream = false;
            _streamTimeoutTimer?.cancel();
            _statusText = 'Starting playback engine...';
            notifyListeners();
          }
        } catch (_) {
          // Stream entry not yet registered — silently wait.
        }
      }, onError: (Object e) => _handleError('Stream engine error: $e'));
    } catch (e) {
      _handleError('Failed to mount stream: $e');
    }
  }

  int? _guessEpisodeNumber(String rawName) {
    final meta = TorrentParser.parse(rawName);
    return meta.episode != -1 ? meta.episode : null;
  }

  /// Fires after [_kStreamTimeout] if the stream still isn't playable —
  /// no-ops if it already succeeded or failed for some other reason in
  /// the meantime (the timer isn't reliably cancelable from every one of
  /// those paths, so this checks state directly rather than assuming the
  /// timer was already stopped).
  void _handleStreamTimeout() {
    if (_isReadyToPlay || _hasError) return;
    _handleError(
      'Timed out waiting for a playable stream — no peers found, or the '
      'swarm never reached a usable download speed.',
    );
  }

  void _updateStatus(String text) {
    if (_hasError) return;
    if (_isReadyToPlay && _statusText == 'Starting playback engine...') return;
    _statusText = text;
    notifyListeners();
  }

  void _handleError(String error) {
    _hasError = true;
    _isMountingStream = false;
    _streamTimeoutTimer?.cancel();
    _statusText = error;
    notifyListeners();
    AppLogger.e('StreamingController', error);
  }

  @override
  void dispose() {
    _streamTimeoutTimer?.cancel();
    unawaited(_torrentSub?.cancel() ?? Future<void>.value());
    unawaited(_streamSub?.cancel() ?? Future<void>.value());

    if (_torrentId != null) {
      try {
        final engine = LibtorrentFlutter.instance;
        engine.stopAllStreamsForTorrent(_torrentId!);
        engine.removeTorrent(_torrentId!, deleteFiles: true);
      } catch (e) {
        AppLogger.i('StreamingController', 'Silent teardown failure: $e');
      }
    }
    super.dispose();
  }
}
