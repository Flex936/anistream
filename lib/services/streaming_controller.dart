import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

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

  Future<void> initialize(String magnetUri) async {
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
      if (_streamUrl == null) {
        _updateStatus('Mounting local HTTP server...');

        // Tells libtorrent to prepare sequential playback for the largest media file
        final streamInfo = engine.startStream(_torrentId!);
        _streamUrl = streamInfo.url;

        // Hand the stream URL to the UI immediately so libmpv can connect
        // and request the end-of-file metadata headers.
        _isReadyToPlay = true;
        _updateStatus('Starting playback engine...');
        notifyListeners();

        // 4. Monitor the stream buffer status (purely for logging now)
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
    });
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
