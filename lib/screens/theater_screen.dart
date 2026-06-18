import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_palette.dart';
import '../services/torrent_scraper.dart';
import '../services/streaming_controller.dart';
import '../widgets/theater/theater_components.dart';
import '../widgets/theater/theater_settings.dart';

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
  late final StreamingController _torrentController;
  late final Player _player;
  late final VideoController _videoController;

  final FocusNode _focusNode = FocusNode();
  bool _videoInitialized = false;
  bool _showControls = true;
  bool _isSettingsOpen = false;
  bool _isFullscreen = false;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();

    // libass: true enables high-quality "burned-in" style subtitle rendering
    _player = Player(configuration: const PlayerConfiguration(libass: true));

    final platform = _player.platform;
    if (platform is NativePlayer) {
      if (Platform.isLinux || Platform.isWindows) {
        platform.setProperty('hwdec', 'cuda-copy'); // NVIDIA Desktop
      } else if (Platform.isAndroid) {
        platform.setProperty('hwdec', 'mediacodec-copy');
      } else if (Platform.isIOS) {
        platform.setProperty('hwdec', 'videotoolbox-copy');
      }
    }

    _videoController = VideoController(_player);
    _torrentController = StreamingController();
    _torrentController.addListener(_onTorrentStateChanged);
    _torrentController.initialize(widget.torrent.magnetLink);

    _startHideControlsTimer();
  }

  void _onTorrentStateChanged() {
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      _videoInitialized = true;
      _player.open(Media(_torrentController.streamUrl!));
      _player.play();
    }
    setState(() {});
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _player.playOrPause();
    }
    // ── Clamp negative seek to 0:00 ──
    else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      final target = _player.state.position - const Duration(seconds: 10);
      _player.seek(target.isNegative ? Duration.zero : target);
    }
    // ── Clamp forward seek to the end of the video ──
    else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      final target = _player.state.position + const Duration(seconds: 10);
      final duration = _player.state.duration;
      _player.seek(target > duration ? duration : target);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _player.setVolume((_player.state.volume + 5).clamp(0, 100));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _player.setVolume((_player.state.volume - 5).clamp(0, 100));
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_isSettingsOpen) {
        setState(() => _isSettingsOpen = false);
      } else if (_isFullscreen) {
        _toggleFullscreen();
      }
    }
    _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _player.state.playing && !_isSettingsOpen) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    await windowManager.setFullScreen(_isFullscreen);
    setState(() {});
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    Future.microtask(() async {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      }
      _torrentController.dispose();
      _player.stop();
      _player.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppPalette.black,
        body: MouseRegion(
          cursor: _showControls
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          onHover: (_) => _startHideControlsTimer(),
          child: GestureDetector(
            onTap: () {
              if (_isSettingsOpen) {
                setState(() => _isSettingsOpen = false);
              } else {
                _player.playOrPause();
              }
              _startHideControlsTimer();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_videoInitialized)
                  Video(
                    controller: _videoController,
                    controls: NoVideoControls,
                  ),

                if (_videoInitialized)
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 200,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    AppPalette.black.withValues(alpha: 0.9),
                                    AppPalette.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 40,
                            left: 24,
                            right: 24,
                            child: TheaterTopBar(
                              episode: widget.episode,
                              onBack: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_isSettingsOpen)
                  Positioned(
                    bottom: 110,
                    right: 32,
                    child: TheaterSettingsMenu(
                      player: _player,
                      onClose: () => setState(() => _isSettingsOpen = false),
                    ),
                  ),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: _torrentController.isReadyToPlay
                      ? const SizedBox.shrink()
                      : TheaterLoadingOverlay(
                          episode: widget.episode,
                          torrent: widget.torrent,
                          controller: _torrentController,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
