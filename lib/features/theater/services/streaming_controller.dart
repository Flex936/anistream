import 'dart:async';

import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/torrent/services/torrent_parser.dart';
import 'streaming_controller_base.dart';

// BatchFileOption is now defined in streaming_controller_base.dart.
// Re-export it so existing imports of this file keep working without changes.
export 'streaming_controller_base.dart' show BatchFileOption;

class StreamingController extends BaseStreamingController {
  // ── PRE-BUFFER GATE ──────────────────────────────────────────────────────
  /// Minimum sequential buffer percentage before the URL is handed to the
  /// player. 2 % gives MPV a solid head-start without making the user wait
  /// long. Raise it if black-frames persist on very slow connections.
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
  StreamSubscription? _torrentSub;
  StreamSubscription? _streamSub;

  bool _needsManualSelection = false;
  @override
  bool get needsManualSelection => _needsManualSelection;

  List<BatchFileOption> _batchFiles = [];
  @override
  List<BatchFileOption> get batchFiles => _batchFiles;

  int? _requestedEpisode;
  bool _filesResolved = false;

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

  @override
  void selectBatchFile(int fileIndex) {
    AppLogger.i(
      'StreamingController',
      'Batch torrent detected — ${_batchFiles.length} files',
    );
    if (_torrentId == null || _isReadyToPlay) return;

    _needsManualSelection = false;
    _statusText = 'Initializing selected file…';
    notifyListeners();
    _beginStream(LibtorrentFlutter.instance, fileIndex: fileIndex);
  }

  void _beginStream(LibtorrentFlutter engine, {int? fileIndex}) {
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
            _statusText = 'Starting playback engine...';
            notifyListeners();
          }
        } catch (_) {
          // Stream entry not yet registered — silently wait.
        }
      });
    } catch (e) {
      _handleError('Failed to mount stream: $e');
    }
  }

  int? _guessEpisodeNumber(String rawName) {
    final meta = TorrentParser.parse(rawName);
    return meta.episode != -1 ? meta.episode : null;
  }

  void _updateStatus(String text) {
    if (_hasError) return;
    if (_isReadyToPlay && _statusText == 'Starting playback engine...') return;
    _statusText = text;
    notifyListeners();
  }

  void _handleError(String error) {
    _hasError = true;
    _statusText = error;
    notifyListeners();
    AppLogger.e('StreamingController', error);
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
        AppLogger.i('StreamingController', 'Silent teardown failure: $e');
      }
    }
    super.dispose();
  }
}
