import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

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

      _torrentId = engine.addMagnet(magnetUri);

      _torrentSub = engine.torrentUpdates.listen(
        (torrents) => _handleTorrentUpdate(engine, torrents),
        onError: (e) => _handleError('Engine sync failed: $e'),
      );
    } catch (e) {
      _handleError('Failed to initialize engine: $e');
    }
  }

  void _handleTorrentUpdate(LibtorrentFlutter engine, Map<int, TorrentInfo> torrents) {
    if (_torrentId == null || !torrents.containsKey(_torrentId)) return;
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
      _batchFiles = videoFiles.map((f) => BatchFileOption(
        index: f.index,
        name: f.name,
        size: f.size,
        guessedEpisode: _guessEpisodeNumber(f.name),
      )).toList()..sort((a, b) => a.index.compareTo(b.index));

      if (_requestedEpisode != null) {
        final matches = _batchFiles.where((f) => f.guessedEpisode == _requestedEpisode).toList();
        if (matches.length == 1) {
          _updateStatus('Found Episode $_requestedEpisode in batch, starting...');
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
    _updateStatus('Starting playback engine...');
    notifyListeners();
    _beginStream(LibtorrentFlutter.instance, fileIndex: fileIndex);
  }

  void _beginStream(LibtorrentFlutter engine, {int? fileIndex}) {
    try {
      final streamInfo = fileIndex == null
          ? engine.startStream(_torrentId!)
          : engine.startStream(_torrentId!, fileIndex: fileIndex);
      
      _streamUrl = streamInfo.url;
      _isReadyToPlay = true;
      _updateStatus('Starting playback engine...');
      notifyListeners();

      _streamSub = engine.streamUpdates.listen((streams) {
        try {
          final s = streams.values.firstWhere((st) => st.url == _streamUrl);
          debugPrint('[Torrent Engine] Sequential Buffer: ${s.bufferPct}%');
        } catch (_) {}
      });
    } catch (e) {
      _handleError('Failed to mount stream: $e');
    }
  }

  int? _guessEpisodeNumber(String rawName) {
    final fileName = rawName.split(RegExp(r'[\\/]')).last.toLowerCase();
    const resolutionNumbers = {480, 720, 1080, 2160};

    final patterns = <RegExp>[
      RegExp(r's\d{1,2}e(\d{1,3})'), 
      RegExp(r'(?:^|[\[\s_.-])ep?(?:isode)?\s*\.?\s*(\d{1,3})(?=[\]\s_.-]|$)'), 
      RegExp(r'-\s*(\d{1,3})(?=\(|\[|v\d|\.|\s|$)'), 
      RegExp(r'(?:^|[\s_.])(\d{1,3})(?=[\s_.]|$)'), 
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(fileName);
      if (match == null) continue;
      final n = int.tryParse(match.group(1)!);
      if (n != null && n > 0 && !resolutionNumbers.contains(n)) {
        return n;
      }
    }
    return null;
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