import 'dart:async';

import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/settings/settings_service.dart';
import '../../../data/torrent/services/torrent_parser.dart';
import 'streaming_controller_base.dart';

export 'streaming_controller_base.dart' show BatchFileOption;

class StreamingController extends BaseStreamingController {
  // Sequential buffer percentage required before the URL goes to the player.
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

  // Set from a batch-file selection until the stream is ready, so a repeat tap
  // (D-pad double-fire) can't call `_beginStream` twice and orphan a stream.
  bool _isMountingStream = false;

  // Ceiling per phase: metadata resolution, then buffering (restarted in
  // `_beginStream`). See ARCHITECTURE.md § 5.
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
    // Restart the ceiling: batch-picker time must not eat the buffering budget.
    _streamTimeoutTimer?.cancel();
    _streamTimeoutTimer = Timer(_kStreamTimeout, _handleStreamTimeout);

    // Cancel any previous subscription; the single-file path also lands here.
    unawaited(_streamSub?.cancel() ?? Future<void>.value());

    try {
      // Caps the engine's RAM piece cache under uiPerformanceMode; read via
      // SettingsCache because this class has no BuildContext.
      final uiPerformanceMode = SettingsCache.current.uiPerformanceMode;

      // Both params are non-nullable, so defaults mean omitting the argument.
      final StreamInfo streamInfo;
      if (fileIndex != null) {
        streamInfo = uiPerformanceMode
            ? engine.startStream(
                _torrentId!,
                fileIndex: fileIndex,
                maxCacheBytes: 100 * 1024 * 1024,
              )
            : engine.startStream(_torrentId!, fileIndex: fileIndex);
      } else {
        streamInfo = uiPerformanceMode
            ? engine.startStream(_torrentId!, maxCacheBytes: 100 * 1024 * 1024)
            : engine.startStream(_torrentId!);
      }

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

  /// Errors after [_kStreamTimeout] unless already succeeded or failed.
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
