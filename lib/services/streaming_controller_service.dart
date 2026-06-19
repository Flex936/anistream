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
    // Initialize the native bindings (safe to fire multiple times)
    await LibtorrentFlutter.init();
    final engine = LibtorrentFlutter.instance;

    // Inject the magnet link into the C++ engine
    _torrentId = engine.addMagnet(magnetUri);

    // Poll for piece and metadata status
    _torrentSub = engine.torrentUpdates.listen((torrents) {
      if (_torrentId == null || !torrents.containsKey(_torrentId)) return;
      final t = torrents[_torrentId]!;

      // Phase A: Resolving Magnet into a file list
      if (!t.hasMetadata) {
        _updateStatus('Fetching metadata... (Peers: ${t.numPeers})');
        return;
      }

      // Phase B: Metadata resolved! Spin up the HTTP stream server
      if (!_filesResolved) {
        _filesResolved = true;
        _resolveFilesAndStartStream(engine);
      }
    });
  }

  void _resolveFilesAndStartStream(LibtorrentFlutter engine) {
    _updateStatus('Reading file list...');

    final files = engine.getFiles(_torrentId!);
    final videoFiles = files.where((f) => f.isStreamable).toList();

    if (videoFiles.length <= 1) {
      // Single-episode torrent (or only one playable file inside it) —
      // identical behavior to before: stream the lone file.
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
        // Exactly one file in the batch claims to be the requested episode
        // — confident enough to start automatically.
        _updateStatus('Found Episode $_requestedEpisode in batch, starting...');
        _beginStream(engine, fileIndex: matches.first.index);
        return;
      }
    }

    // Ambiguous (no match, multiple files claim the same number, or no
    // episode was requested at all) — hand the decision to the user.
    _needsManualSelection = true;
    _updateStatus('Batch torrent detected — choose an episode');
    notifyListeners();
  }

  /// Called by the UI once the user manually picks a file from a batch torrent.
  void selectBatchFile(int fileIndex) {
    if (_torrentId == null || _isReadyToPlay) return;
    _needsManualSelection = false;
    _updateStatus('Starting playback engine...');
    notifyListeners();
    _beginStream(LibtorrentFlutter.instance, fileIndex: fileIndex);
  }

  void _beginStream(LibtorrentFlutter engine, {int? fileIndex}) {
    // Tells libtorrent to prepare sequential playback for the chosen file
    // (or the largest media file, if no index is given).
    final streamInfo = fileIndex == null
        ? engine.startStream(_torrentId!)
        : engine.startStream(_torrentId!, fileIndex: fileIndex);
    _streamUrl = streamInfo.url;

    // Hand the stream URL to the UI immediately so libmpv can connect
    // and request the end-of-file metadata headers.
    _isReadyToPlay = true;
    _updateStatus('Starting playback engine...');
    notifyListeners();

    // Monitor the stream buffer status (purely for logging now)
    _streamSub = engine.streamUpdates.listen((streams) {
      try {
        final s = streams.values.firstWhere((st) => st.url == _streamUrl);
        // We no longer gate the UI with this, but it's useful for debugging
        debugPrint('[Torrent Engine] Sequential Buffer: ${s.bufferPct}%');
      } catch (_) {
        // Stream not registered in the map yet
      }
    });
  }

  /// Best-effort episode-number guess from a filename living inside a torrent.
  /// Handles common batch-naming conventions:
  ///   "[Group] Show - 05 (1080p) [HASH].mkv"   -> 5
  ///   "Show.Name.S01E05.1080p.WEB-DL.mkv"       -> 5
  ///   "05 - Show Name.mkv"                      -> 5
  ///   "[Group] Show - 5v2.mkv"                  -> 5
  /// Returns null when nothing reliable can be extracted, which pushes that
  /// file towards manual selection instead of a wrong auto-pick.
  int? _guessEpisodeNumber(String rawName) {
    // Files inside a torrent are often nested under a folder, e.g.
    // "Show Name/Show Name - 05.mkv" — only look at the actual filename.
    final fileName = rawName.split(RegExp(r'[\\/]')).last.toLowerCase();
    const resolutionNumbers = {480, 720, 1080, 2160};

    final patterns = <RegExp>[
      RegExp(r's\d{1,2}e(\d{1,3})'), // S01E05
      RegExp(
        r'(?:^|[\[\s_.-])ep?(?:isode)?\s*\.?\s*(\d{1,3})(?=[\]\s_.-]|$)',
      ), // E05 / Ep 05 / Episode 05
      RegExp(r'-\s*(\d{1,3})(?=\(|\[|v\d|\.|\s|$)'), // " - 05 " / " - 05v2"
      RegExp(
        r'(?:^|[\s_.])(\d{1,3})(?=[\s_.]|$)',
      ), // bare number between separators (last resort)
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
    // Lock the status text once playback begins so it stops jumping around
    if (_isReadyToPlay && _statusText == 'Playback starting...') return;

    _statusText = text;
    notifyListeners();
  }

  @override
  void dispose() {
    _torrentSub?.cancel();
    _streamSub?.cancel();

    // Safely teardown the native bindings to prevent memory leaks when the user goes back
    if (_torrentId != null) {
      try {
        final engine = LibtorrentFlutter.instance;
        engine.stopAllStreamsForTorrent(_torrentId!);

        // Fulfills the "Zero Junk Files" requirement: completely purges the cache
        engine.removeTorrent(_torrentId!, deleteFiles: true);
      } catch (_) {
        // Suppress teardown errors if the engine is already disposed
      }
    }
    super.dispose();
  }
}
