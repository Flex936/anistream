import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../../../data/torrent/services/torrent_parser.dart';

class BatchFileOption {
  final int index;
  final String name;
  final int size;
  final int? guessedEpisode;

  const BatchFileOption({
    required this.index,
    required this.name,
    required this.size,
    this.guessedEpisode,
  });
}

class StreamingController extends ChangeNotifier {
  // ── PRE-BUFFER GATE ──────────────────────────────────────────────────────────
  /// Minimum sequential buffer percentage before the URL is handed to the
  /// player. 2 % gives MPV a solid head-start without making the user wait
  /// long. Raise it if black-frames persist on very slow connections.
  static const double _kPreBufferThreshold = 0.1;

  String _statusText = 'Initializing Native Engine...';
  String get statusText => _statusText;

  String? _streamUrl;
  String? get streamUrl => _streamUrl;

  bool _isReadyToPlay = false;
  bool get isReadyToPlay => _isReadyToPlay;

  bool _hasError = false;
  bool get hasError => _hasError;

  int? _torrentId;
  StreamSubscription? _torrentSub;
  StreamSubscription? _streamSub;

  bool _needsManualSelection = false;
  bool get needsManualSelection => _needsManualSelection;

  List<BatchFileOption> _batchFiles = [];
  List<BatchFileOption> get batchFiles => _batchFiles;

  int? _requestedEpisode;
  bool _filesResolved = false;

  Future<void> initialize(String magnetUri, {int? episodeNumber}) async {
    _requestedEpisode = episodeNumber;
    try {
      await LibtorrentFlutter.init();
      final engine = LibtorrentFlutter.instance;

      _torrentSub = engine.torrentUpdates.listen(
        (torrents) => _handleTorrentUpdate(engine, torrents),
        onError: (e) => _handleError('Engine sync failed: $e'),
      );

      _torrentId = engine.addMagnet(magnetUri);
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

      // ── Batch torrent: multiple episodes packed into one torrent ──
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

  void selectBatchFile(int fileIndex) {
    if (_torrentId == null || _isReadyToPlay) return;

    _needsManualSelection = false;
    _statusText = 'Initializing selected file…';
    notifyListeners(); // Immediately dismiss the picker before stream setup begins
    _beginStream(LibtorrentFlutter.instance, fileIndex: fileIndex);
  }

  void _beginStream(LibtorrentFlutter engine, {int? fileIndex}) {
    try {
      final streamInfo = fileIndex == null
          ? engine.startStream(_torrentId!)
          : engine.startStream(_torrentId!, fileIndex: fileIndex);

      // ── PRE-BUFFER GATE ─────────────────────────────────────────────────────
      // We have the localhost URL, but the torrent has written zero bytes yet.
      // _isReadyToPlay stays false — the TheaterLoadingOverlay remains visible.
      // The gate opens only once the sequential buffer reaches the threshold,
      // giving MPV a contiguous chunk of data to parse headers and start
      // decoding without hitting an immediate EOF / black screen.
      _streamUrl = streamInfo.url;
      _updateStatus('Buffering… 0.0%');

      _streamSub = engine.streamUpdates.listen((streams) {
        if (_hasError) return;

        try {
          final s = streams.values.firstWhere((st) => st.url == _streamUrl);
          final pct = s.bufferPct;

          // Gate is already open — log for diagnostics, no more UI churn.
          if (_isReadyToPlay) {
            debugPrint(
              '[Torrent Engine] Sequential Buffer: ${pct.toStringAsFixed(1)}%',
            );
            return;
          }

          // Throttle rebuilds: only notify when the displayed text changes.
          // streamUpdates can fire many times per second; skipping no-op
          // notifies keeps the widget tree quiet during rapid piece downloads.
          final label = 'Buffering… ${pct.toStringAsFixed(1)}%';
          if (_statusText != label) {
            _statusText = label;
            notifyListeners();
          }

          // Open the gate: hand control to the player for the first time.
          if (pct >= _kPreBufferThreshold) {
            _isReadyToPlay = true;
            _statusText = 'Starting playback engine...';
            notifyListeners();
          }
        } catch (_) {
          // Stream entry not yet registered in the map — silently wait.
        }
      });
    } catch (e) {
      _handleError('Failed to mount stream: $e');
    }
  }

  // ── PRE-COMPILED PARSER ──
  int? _guessEpisodeNumber(String rawName) {
    final meta = TorrentParser.parse(rawName);
    if (meta.episode != -1) {
      return meta.episode;
    } else {
      return null;
    }
  }

  void _updateStatus(String text) {
    if (_hasError) return;
    // Once the gate is open and the final status is set, freeze it.
    if (_isReadyToPlay && _statusText == 'Starting playback engine...') return;
    _statusText = text;
    notifyListeners();
  }

  void _handleError(String error) {
    _hasError = true;
    _statusText = error;
    notifyListeners();
    debugPrint('[StreamingController Error] $error');
  }

  @override
  void dispose() {
    _torrentSub?.cancel();
    _streamSub?.cancel();

    if (_torrentId != null) {
      try {
        final engine = LibtorrentFlutter.instance;
        engine.stopAllStreamsForTorrent(_torrentId!);
        engine.removeTorrent(_torrentId!, deleteFiles: true);
      } catch (e) {
        debugPrint('[StreamingController] Silent teardown failure: $e');
      }
    }
    super.dispose();
  }
}
