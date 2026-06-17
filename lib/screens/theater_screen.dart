import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../theme/app_palette.dart';
import '../services/torrent_scraper.dart';
import '../services/streaming_controller.dart';

class TheaterScreen extends StatefulWidget {
  final int episode;
  final Torrent torrent;

  const TheaterScreen({
    super.key,
    required this.episode,
    required this.torrent,
  });

  @override
  State<TheaterScreen> createState() => _TheaterScreenState();
}

class _TheaterScreenState extends State<TheaterScreen> {
  // Our new P2P business logic controller
  late final StreamingController _torrentController;

  // The media_kit UI controllers
  late final Player _player;
  late final VideoController _videoController;

  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    debugPrint('\n[TheaterScreen] INITIALIZING EPISODE ${widget.episode}');

    // Initialize the media player (it stays completely dormant right now)
    _player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
        libassAndroidFont: 'assets/fonts/Roboto-Regular.ttf',
      ),
    );

    // Pipe the native mpv logs directly to the Flutter terminal
    _player.stream.log.listen((event) {
      debugPrint('[media_kit_native] ${event.level}: ${event.text}');
    });

    _videoController = VideoController(_player);

    // Initialize the torrent stream and listen to its lifecycle
    debugPrint('[TheaterScreen] Starting P2P Engine...');
    _torrentController = StreamingController();
    _torrentController.addListener(_onTorrentStateChanged);
    _torrentController.initialize(widget.torrent.magnetLink);
  }

  void _onTorrentStateChanged() {
    // Log the current status of the engine
    debugPrint(
      '[TheaterScreen] P2P Status: ${_torrentController.statusText} | Ready: ${_torrentController.isReadyToPlay}',
    );

    // Once the engine reports the file headers are parsed and pieces are buffered...
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      debugPrint(
        '[TheaterScreen] Engine is ready! Feeding localhost stream to media_kit...',
      );
      debugPrint('[TheaterScreen] Stream URL: ${_torrentController.streamUrl}');

      _videoInitialized = true;
      // Feed the local HTTP stream URL directly to the native GPU player
      _player.open(Media(_torrentController.streamUrl!));
    }

    // Trigger a UI rebuild to update the loading text
    setState(() {});
  }

  @override
  void dispose() {
    debugPrint('\n[TheaterScreen] DISPOSING THEATER SCREEN...');

    // Remove listeners first
    _torrentController.removeListener(_onTorrentStateChanged);

    // Use a microtask to ensure the engine finishes its current frame
    // before we flush the video memory.
    Future.microtask(() {
      debugPrint('[TheaterScreen] Tearing down P2P engine and Video player...');
      _torrentController.dispose();
      _player.stop();
      _player.dispose();
      debugPrint('[TheaterScreen] Teardown complete.');
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: AppPalette.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppPalette.white),
          onPressed: () {
            debugPrint('[TheaterScreen] Back button pressed');
            Navigator.pop(context);
          },
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 1: The Hardware Accelerated Video Canvas ──
          if (_videoInitialized)
            Video(
              controller: _videoController,
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                visible: false,
              ),
            ),

          // ── Layer 2: The Loading Overlay ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: _torrentController.isReadyToPlay
                ? const SizedBox.shrink() // Disappears when ready
                : Container(
                    key: const ValueKey('loading_overlay'),
                    color: AppPalette.black.withValues(alpha: 0.85),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Spinner
                          const SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppPalette.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Context
                          Text(
                            'Episode ${widget.episode}',
                            style: const TextStyle(
                              color: AppPalette.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Group Chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppPalette.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppPalette.border),
                            ),
                            child: Text(
                              '${widget.torrent.releaseGroup} · ${widget.torrent.resolution}',
                              style: const TextStyle(
                                color: AppPalette.textMuted,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Live P2P Engine Status Text
                          Text(
                            _torrentController.statusText,
                            style: const TextStyle(
                              color: AppPalette.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
