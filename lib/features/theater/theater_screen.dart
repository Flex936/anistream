import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_palette.dart';
import '../../data/torrent/models/torrent.dart';
import 'services/streaming_controller_service.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_controls.dart';
import 'widgets/theater_settings.dart';
import 'widgets/theater_batch_picker.dart';

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
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(libass: true));
    _videoController = VideoController(_player);
    _torrentController = StreamingController();
    _torrentController.addListener(_onTorrentStateChanged);

    _initPlayerAndStream();
    _startHideControlsTimer();
  }

  Future<void> _initPlayerAndStream() async {
    final prefs = await SharedPreferences.getInstance();
    final hwdec = prefs.getString('hwdec_preference') ?? 'auto';

    final platform = _player.platform;
    if (platform is NativePlayer) {
      // Optional debug logging, uncomment if needed:
      // await platform.setProperty('msg-level', 'all=v');

      if (hwdec == 'auto') {
        if (Platform.isLinux || Platform.isWindows) {
          platform.setProperty('hwdec', 'auto-safe');
          windowManager.setFullScreen(true);
        } else if (Platform.isAndroid) {
          platform.setProperty('hwdec', 'mediacodec-copy');
        } else if (Platform.isIOS || Platform.isMacOS) {
          platform.setProperty('hwdec', 'videotoolbox-copy');
        }
      } else if (hwdec != 'none') {
        platform.setProperty('hwdec', hwdec);
      }
    }

    _torrentController.initialize(
      widget.torrent.magnetLink,
      episodeNumber: widget.episode,
    );
  }

  void _onTorrentStateChanged() {
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      setState(() => _videoInitialized = true);
      _player.open(Media(_torrentController.streamUrl!));
      _player.play();
    } else {
      setState(() {});
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.select) {
      _player.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      final target = _player.state.position - const Duration(seconds: 10);
      _player.seek(target.isNegative ? Duration.zero : target);
    } else if (key == LogicalKeyboardKey.arrowRight ||
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
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      if (_isSettingsOpen) {
        setState(() => _isSettingsOpen = false);
      } else if (_isFullscreen) {
        _toggleFullscreen();
      }
    } else if (key == LogicalKeyboardKey.contextMenu) {
      setState(() => _isSettingsOpen = !_isSettingsOpen);
    }

    _startHideControlsTimer();
    return KeyEventResult.handled;
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!mounted) return;
    setState(() => _showControls = true);

    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _player.state.playing && !_isSettingsOpen) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    await windowManager.setFullScreen(_isFullscreen);
    if (mounted) setState(() {});
  }

  Future<void> _exitTheater() async {
    if (_isClosing) return;
    _isClosing = true;

    if (mounted) {
      setState(() => _videoInitialized = false);
      await WidgetsBinding.instance.endOfFrame;
    }

    _hideControlsTimer?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);

    await _player.pause();
    await _player.stop();
    await _player.dispose();
    _torrentController.dispose();

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);

    if (!_isClosing) {
      _isClosing = true;
      Future.microtask(() async {
        await _player.stop();
        await _player.dispose();
        _torrentController.dispose();
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) windowManager.setFullScreen(true);
          });
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppPalette.black,
        body: ExcludeSemantics(
          child: MouseRegion(
            cursor: _showControls
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            onHover: (_) => _startHideControlsTimer(),
            child: GestureDetector(
              onTap: () {
                if (_isSettingsOpen) {
                  setState(() => _isSettingsOpen = false);
                } else if (_videoInitialized) {
                  _player.playOrPause();
                }
                _startHideControlsTimer();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: _videoInitialized ? 1.0 : 0.0,
                    child: Video(
                      controller: _videoController,
                      controls: NoVideoControls,
                    ),
                  ),
                  // Always mounted, even while loading — gives media_kit_video time to
                  // set up its texture/surface well before playback actually starts.
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
                              top: 40,
                              left: 24,
                              right: 24,
                              child: GestureDetector(
                                onTap: () {},
                                child: TheaterTopBar(
                                  episode: widget.episode,
                                  onBack: _exitTheater,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 24,
                              left: 32,
                              right: 32,
                              child: GestureDetector(
                                onTap: () {},
                                child: TheaterControls(
                                  player: _player,
                                  isSettingsOpen: _isSettingsOpen,
                                  onInteract: _startHideControlsTimer,
                                  onToggleSettings: () => setState(
                                    () => _isSettingsOpen = !_isSettingsOpen,
                                  ),
                                ),
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
                        : _torrentController.needsManualSelection
                        ? BatchEpisodePickerOverlay(
                            files: _torrentController.batchFiles,
                            requestedEpisode: widget.episode,
                            onSelect: _torrentController.selectBatchFile,
                          )
                        : TheaterLoadingOverlay(
                            episode: widget.episode,
                            controller: _torrentController,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
