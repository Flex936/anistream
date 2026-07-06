import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_service.dart';
import '../../data/torrent/models/torrent.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/anilist/anilist_tracker_service.dart';
import '../../shared/widgets/toast.dart';
import 'services/streaming_controller_base.dart';
import 'services/streaming_controller.dart';
import 'services/remote_streaming_controller.dart';
import 'services/theater_data.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_controls.dart';
import 'widgets/theater_settings.dart';
import 'widgets/batch_picker.dart';
import '../pip/pip_args.dart';

class TheaterScreen extends StatefulWidget {
  final Anime anime;
  final int episode;
  final Torrent torrent;

  const TheaterScreen({
    super.key,
    required this.anime,
    required this.episode,
    required this.torrent,
  });

  @override
  State<TheaterScreen> createState() => _TheaterScreenState();
}

class _TheaterScreenState extends State<TheaterScreen> {
  // ── Streaming controller ─────────────────────────────────────────────────
  // Starts as a placeholder StreamingController (with no listener added).
  // _initPlayerAndStream() replaces it with the right type once settings are
  // loaded. The type is BaseStreamingController so TheaterScreen never needs
  // to know which mode is active.
  BaseStreamingController _torrentController = StreamingController();

  late final AnilistTrackerService _tracker;
  late final Player _player;
  late final VideoController _videoController;

  final FocusNode _focusNode = FocusNode();
  bool _videoInitialized = false;
  bool _showControls = true;
  bool _isSettingsOpen = false;
  bool _isFullscreen = true;
  Timer? _hideControlsTimer;
  bool _isClosing = false;
  WindowController? _ownWindowController;

  // ── Auto-skip ────────────────────────────────────────────────────────────
  bool _autoSkip = false;
  bool _isAutoSkipping = false;
  Chapter? _currentAutoSkipChapter;
  Timer? _autoSkipTimer;

  // ── Performance settings ─────────────────────────────────────────────────
  bool _uiPerformanceMode = false;
  String _videoFilterQuality = 'low';

  List<Chapter> _chapters = [];
  StreamSubscription? _posSub;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(libass: true));
    const videoConfig = VideoControllerConfiguration(
      androidAttachSurfaceAfterVideoParameters: true,
    );
    _videoController = VideoController(_player, configuration: videoConfig);

    // Placeholder has no listener yet — _initPlayerAndStream adds one to the
    // real controller after it decides which type to create.

    _tracker = AnilistTrackerService(
      onSuccess: () {
        if (mounted) {
          AppleTopSnackBar.show(
            context: context,
            message: 'Progress saved to AniList',
            icon: Icons.check_circle_rounded,
            iconColor: AppPalette.statusReleasing,
          );
        }
      },
    );

    _initPlayerAndStream();
    _startHideControlsTimer();

    if (Platform.isLinux || Platform.isMacOS) {
      _registerPipReturnHandler();
    }
  }

  Future<void> _initPlayerAndStream() async {
    if (!mounted) return;

    // ── Load all settings in one call ─────────────────────────────────────
    // This replaces the original two separate prefs reads (SettingsService
    // in initState + SharedPreferencesAsync in this method).
    final s = await SettingsService().load();
    if (!mounted) return;

    // Apply performance and playback flags immediately.
    setState(() {
      _uiPerformanceMode = s.uiPerformanceMode;
      _videoFilterQuality = s.videoFilterQuality;
      _autoSkip = s.autoSkip;
    });

    // ── Pick controller ───────────────────────────────────────────────────
    // Build the correct controller based on whether server mode is on.
    final BaseStreamingController newController;
    if (s.serverMode && s.serverUrl.isNotEmpty) {
      newController = RemoteStreamingController(serverUrl: s.serverUrl);
    } else {
      newController = StreamingController();
    }
    newController.addListener(_onTorrentStateChanged);

    if (!mounted) {
      // Widget was disposed before we could swap — clean up the orphan.
      newController.dispose();
      return;
    }

    // Swap: ListenableBuilder will unsubscribe from the placeholder and
    // subscribe to newController in the next rebuild triggered by setState.
    final oldPlaceholder = _torrentController;
    setState(() => _torrentController = newController);

    // Dispose the placeholder AFTER the rebuild so ListenableBuilder can
    // safely call removeListener on it first.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => oldPlaceholder.dispose(),
    );

    // ── Hardware decoding ─────────────────────────────────────────────────
    final platform = _player.platform;
    if (platform is NativePlayer) {
      final hwdec = s.hardwareDecoding;
      final androidHwDec = s.androidHwDec;

      if (hwdec == 'auto') {
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
          platform.setProperty('hwdec', 'auto-safe');
          windowManager.setFullScreen(true);
        } else if (Platform.isAndroid) {
          platform.setProperty('hwdec', androidHwDec);
        } else if (Platform.isIOS) {
          platform.setProperty('hwdec', 'videotoolbox');
        }
      } else if (hwdec != 'none') {
        platform.setProperty('hwdec', hwdec);
      }

      // P2P demuxer tuning — keeps MPV happy on bursty torrent streams.
      // In server mode the stream comes off a LAN HTTP server, so these
      // settings still help MPV absorb any micro-stalls.
      platform.setProperty('cache', 'yes');
      platform.setProperty('demuxer-max-bytes', '150000000');
      platform.setProperty('demuxer-readahead-secs', '120');
    }

    // ── Restore persistent volume ─────────────────────────────────────────
    final savedVolume =
        await SharedPreferencesAsync().getDouble('theater_volume') ?? 100.0;
    _player.setVolume(savedVolume);

    // ── Start streaming ───────────────────────────────────────────────────
    // Fire and forget — state changes come back via _onTorrentStateChanged.
    _torrentController.initialize(
      widget.torrent.magnetLink,
      episodeNumber: widget.episode,
    );

    // ── AniList progress tracking ─────────────────────────────────────────
    await _tracker.init(
      mediaId: widget.anime.id,
      episode: widget.episode,
      totalEpisodes: widget.anime.episodes,
    );
    if (!mounted) return;

    _posSub = _player.stream.position.listen((pos) {
      _tracker.updateProgress(pos, _player.state.duration);
      _handleAutoSkip(pos);
    });
  }

  // ── Controller listener ───────────────────────────────────────────────────

  void _onTorrentStateChanged() {
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      setState(() => _videoInitialized = true);
      // In local mode:  streamUrl = http://127.0.0.1:<port>/...
      // In server mode: streamUrl = http://<server-ip>:7878/api/stream/:id/video
      // MPV handles both identically via range requests.
      _player.open(Media(_torrentController.streamUrl!));

      _player.stream.duration.firstWhere((d) => d > Duration.zero).then((
        _,
      ) async {
        final resolvedChapters = await loadChapters(_player);

        debugPrint('\n─── LOADED CHAPTERS ───');
        for (int i = 0; i < resolvedChapters.length; i++) {
          final c = resolvedChapters[i];
          debugPrint(
            '[$i] "${c.title}" | ${c.start} -> ${c.end} | Skippable: ${c.isSkippable}',
          );
        }
        debugPrint('───────────────────────────\n');

        if (mounted) setState(() => _chapters = resolvedChapters);
      });

      _player.play();
    }
  }

  // ── Auto-skip ─────────────────────────────────────────────────────────────

  void _handleAutoSkip(Duration pos) {
    if (!_autoSkip || _chapters.isEmpty) return;

    Chapter? activeChapter;
    for (final c in _chapters) {
      if (c.isSkippable &&
          pos >= c.start &&
          pos < (c.end - const Duration(seconds: 1))) {
        activeChapter = c;
        break;
      }
    }

    if (activeChapter == null) {
      if (_isAutoSkipping) {
        debugPrint('Auto-skip cancelled (user intervened or chapter ended)');
        _autoSkipTimer?.cancel();
        _isAutoSkipping = false;
        _currentAutoSkipChapter = null;
      }
      return;
    }

    if (_currentAutoSkipChapter != activeChapter) {
      debugPrint(
        'Auto-skip triggered for: "${activeChapter.title}" (${activeChapter.start} -> ${activeChapter.end})',
      );

      _autoSkipTimer?.cancel();
      _isAutoSkipping = true;
      _currentAutoSkipChapter = activeChapter;

      if (mounted) {
        AppleTopSnackBar.show(
          context: context,
          message: 'Auto-skipping ${activeChapter.skipLabel} in 2s...',
          icon: Icons.fast_forward_rounded,
          iconColor: AppPalette.primary,
        );
      }

      _autoSkipTimer = Timer(const Duration(seconds: 2), () {
        if (mounted &&
            _isAutoSkipping &&
            _currentAutoSkipChapter == activeChapter) {
          debugPrint('⏭ Executing skip to: ${activeChapter!.end}');
          _player.seek(activeChapter.end);
          _isAutoSkipping = false;
        }
      });
    }
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isShift =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    if (_isSettingsOpen || _torrentController.needsManualSelection) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        setState(() => _isSettingsOpen = false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.select) {
      _player.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      if (isShift && _chapters.isNotEmpty) {
        final prevChap = _chapters.lastWhere(
          (c) => c.start < _player.state.position - const Duration(seconds: 3),
          orElse: () => const Chapter(
            title: 'start',
            start: Duration.zero,
            end: Duration.zero,
          ),
        );
        _player.seek(prevChap.start);
      } else {
        final target = _player.state.position - const Duration(seconds: 10);
        _player.seek(target.isNegative ? Duration.zero : target);
      }
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      if (isShift && _chapters.isNotEmpty) {
        final nextChap = _chapters.firstWhere(
          (c) => c.start > _player.state.position + const Duration(seconds: 1),
          orElse: () => Chapter(
            title: 'end',
            start: _player.state.duration,
            end: _player.state.duration,
          ),
        );
        _player.seek(nextChap.start);
      } else {
        final target = _player.state.position + const Duration(seconds: 10);
        final duration = _player.state.duration;
        _player.seek(target > duration ? duration : target);
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      final newVol = (_player.state.volume + 5).clamp(0.0, 100.0);
      _player.setVolume(newVol);
      if (newVol > 0) {
        SharedPreferencesAsync().setDouble('theater_volume', newVol);
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final newVol = (_player.state.volume - 5).clamp(0.0, 100.0);
      _player.setVolume(newVol);
      if (newVol > 0) {
        SharedPreferencesAsync().setDouble('theater_volume', newVol);
      }
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      if (_isSettingsOpen) {
        setState(() => _isSettingsOpen = false);
      } else if (_isFullscreen) {
        _toggleFullscreen();
      } else {
        _exitTheater();
      }
    } else if (key == LogicalKeyboardKey.contextMenu) {
      setState(() => _isSettingsOpen = !_isSettingsOpen);
    }

    _startHideControlsTimer();
    return KeyEventResult.handled;
  }

  // ── Controls visibility ───────────────────────────────────────────────────

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

  // ── Window / exit ─────────────────────────────────────────────────────────

  Future<void> _toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    await windowManager.setFullScreen(_isFullscreen);
    if (mounted) setState(() {});
  }

  Future<void> _disposePlaybackResources() async {
    await _player.stop();
    await _player.dispose();
    _torrentController.dispose();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
    }
  }

  Future<void> _exitTheater() async {
    if (_isClosing) return;
    _isClosing = true;

    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    if (mounted) {
      setState(() => _videoInitialized = false);
      await WidgetsBinding.instance.endOfFrame;
    }
    _hideControlsTimer?.cancel();
    _autoSkipTimer?.cancel();
    _posSub?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();
    await _disposePlaybackResources();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _registerPipReturnHandler() async {
    _ownWindowController = await WindowController.fromCurrentEngine();
    _ownWindowController!.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'pip_returned':
          final positionMs = (call.arguments as Map)['positionMs'] as int;
          _player.seek(Duration(milliseconds: positionMs));
          _player.play();
          await windowManager.show();
          await windowManager.focus();
        case 'pip_ready':
          await windowManager.minimize();
      }
      return null;
    });
  }

  Future<WindowController?> _findExistingPipWindow() async {
    if (Platform.isAndroid || Platform.isIOS) return null;

    final all = await WindowController.getAll();
    for (final controller in all) {
      if (PipArgs.fromRaw(controller.arguments.toString()).isPip) {
        return controller;
      }
    }
    return null;
  }

  Future<void> _popOutToPip() async {
    if (Platform.isAndroid || Platform.isIOS) return;

    final streamUrl = _torrentController.streamUrl;
    if (streamUrl == null || _ownWindowController == null) return;

    final existing = await _findExistingPipWindow();
    if (existing != null) {
      await existing.invokeMethod('focus_pip');
      await windowManager.minimize();
      return;
    }

    final position = _player.state.position;
    _player.pause();

    final args = PipArgs.pip(
      streamUrl: streamUrl,
      title: widget.anime.title.display,
      episode: widget.episode,
      positionMs: position.inMilliseconds,
      mainWindowId: _ownWindowController!.windowId,
    );

    final pipController = await WindowController.create(
      WindowConfiguration(hiddenAtLaunch: true, arguments: args.toRaw()),
    );
    await pipController.show();
  }

  Future<void> _forceClosePip() async {
    if (Platform.isAndroid || Platform.isIOS) return;
    final existing = await _findExistingPipWindow();
    await existing?.invokeMethod('force_close');
  }

  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    _autoSkipTimer?.cancel();
    _posSub?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();
    _forceClosePip();

    if (!_isClosing) {
      _isClosing = true;
      Future.microtask(_disposePlaybackResources);
    }
    super.dispose();
  }

  // ── Video quality ─────────────────────────────────────────────────────────

  FilterQuality _getFilterQuality() => switch (_videoFilterQuality) {
    'high' => FilterQuality.high,
    'medium' => FilterQuality.medium,
    'none' => FilterQuality.none,
    _ => FilterQuality.low,
  };

  // ── Build ─────────────────────────────────────────────────────────────────

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
                  // ── Video ─────────────────────────────────────────────────
                  AnimatedOpacity(
                    opacity: _videoInitialized ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Video(
                      controller: _videoController,
                      controls: NoVideoControls,
                      filterQuality: _getFilterQuality(),
                    ),
                  ),

                  // ── Playback controls overlay ─────────────────────────────
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
                                  uiPerformanceMode: _uiPerformanceMode,
                                  onBack: _exitTheater,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () {},
                                child: TheaterControls(
                                  player: _player,
                                  chapterMetadata: _chapters,
                                  isSettingsOpen: _isSettingsOpen,
                                  isFullscreen: _isFullscreen,
                                  uiPerformanceMode: _uiPerformanceMode,
                                  onToggleFullscreen: _toggleFullscreen,
                                  onInteract: _startHideControlsTimer,
                                  onToggleSettings: () => setState(
                                    () => _isSettingsOpen = !_isSettingsOpen,
                                  ),
                                  onPip: _popOutToPip,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Track / subtitle picker ───────────────────────────────
                  if (_isSettingsOpen)
                    Positioned(
                      bottom: 110,
                      right: 32,
                      child: TheaterSettingsMenu(
                        player: _player,
                        uiPerformanceMode: _uiPerformanceMode,
                        onClose: () => setState(() => _isSettingsOpen = false),
                      ),
                    ),

                  // ── Loading / batch-picker overlay ────────────────────────
                  // ListenableBuilder re-renders whenever _torrentController
                  // calls notifyListeners(). Works identically for both the
                  // local and remote controller since they share the same base.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    child: ListenableBuilder(
                      listenable: _torrentController,
                      builder: (context, _) {
                        if (_torrentController.isReadyToPlay) {
                          return const SizedBox.shrink();
                        }
                        if (_torrentController.needsManualSelection) {
                          return BatchEpisodePickerOverlay(
                            files: _torrentController.batchFiles,
                            requestedEpisode: widget.episode,
                            onSelect: _torrentController.selectBatchFile,
                          );
                        }
                        return TheaterLoadingOverlay(
                          episode: widget.episode,
                          controller: _torrentController,
                        );
                      },
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
