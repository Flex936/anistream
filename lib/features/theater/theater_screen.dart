import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/input/input_mode_controller.dart';
import '../../core/input/input_mode_scope.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_tracker_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/torrent/models/torrent.dart';
import '../../shared/widgets/toast.dart';
import 'services/auto_skip_controller.dart';
import 'services/player_configurator.dart';
import 'services/remote_streaming_controller.dart';
import 'services/streaming_controller.dart';
import 'services/streaming_controller_base.dart';
import 'services/theater_data.dart';
import 'widgets/batch_picker.dart';
import 'widgets/theater_controls.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_settings.dart';

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
  BaseStreamingController _torrentController = StreamingController();

  late final AnilistTrackerService _tracker;
  late final Player _player;
  late final VideoController _videoController;
  late final AutoSkipController _autoSkipController;

  final FocusNode _focusNode = FocusNode();
  bool _videoInitialized = false;
  bool _showControls = true;
  bool _isSettingsOpen = false;
  bool _isFullscreen = true;
  Timer? _hideControlsTimer;
  bool _isClosing = false;

  // ── Auto-skip setting (the state machine itself now lives in
  // AutoSkipController) ──
  bool _autoSkip = false;

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

    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    _autoSkipController = AutoSkipController(
      player: _player,
      isEnabled: () => _autoSkip,
      onSkipArmed: (skipLabel) {
        if (mounted) {
          AppleTopSnackBar.show(
            context: context,
            message: 'Auto-skipping $skipLabel in 2s...',
            icon: Icons.fast_forward_rounded,
            iconColor: AppPalette.primary,
          );
        }
      },
    );

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
  }

  Future<void> _initPlayerAndStream() async {
    if (!mounted) return;

    final s = SettingsScope.of(context, listen: false).settings;

    setState(() {
      _uiPerformanceMode = s.uiPerformanceMode;
      _videoFilterQuality = s.videoFilterQuality;
      _autoSkip = s.autoSkip;
    });

    final BaseStreamingController newController;
    if (s.serverMode && s.serverUrl.isNotEmpty) {
      newController = RemoteStreamingController(serverUrl: s.serverUrl);
    } else {
      newController = StreamingController();
    }
    newController.addListener(_onTorrentStateChanged);

    if (!mounted) {
      newController.dispose();
      return;
    }

    final oldPlaceholder = _torrentController;
    setState(() => _torrentController = newController);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => oldPlaceholder.dispose(),
    );

    // ── Hardware decoding + streaming tuning
    PlayerConfigurator.configureForTheater(_player, s);

    // Preserves the original quirk: fullscreen is only forced here when
    // hwdec is left on "auto" and we're on a desktop platform (matches the
    // prior inline logic exactly).
    if (s.hardwareDecoding == 'auto' &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      windowManager.setFullScreen(true);
    }

    // ── Restore persistent volume ─────────────────────────────────────────
    final savedVolume =
        await SharedPreferencesAsync().getDouble('theater_volume') ?? 100.0;
    _player.setVolume(savedVolume);

    // ── Start streaming ───────────────────────────────────────────────────
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
      _autoSkipController.onPosition(pos);
    });
  }

  // ── Controller listener ───────────────────────────────────────────────────

  void _onTorrentStateChanged() {
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      setState(() => _videoInitialized = true);
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

        if (mounted) {
          setState(() => _chapters = resolvedChapters);
          _autoSkipController.chapters = resolvedChapters;
        }
      });

      _player.play();
    }
  }

  // ── Keyboard / D-Pad ──────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // A settings/batch-picker sub-menu is its own FocusScope with its own
    // autofocus'd content, so once it's open we only care about Escape/Back
    // here — everything else (including arrows for its own internal
    // navigation) is left `ignored` so it bubbles to that sub-menu's scope
    // instead of us swallowing it. This also deliberately does NOT restart
    // the hide-controls timer — the main control bar isn't supposed to be
    // fighting for the same screen space as an open sub-menu.
    if (_isSettingsOpen || _torrentController.needsManualSelection) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        setState(() => _isSettingsOpen = false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Any other key, while the main control surface is what's active,
    // counts as activity — reveal the controls even if we go on to leave
    // the event itself unconsumed below.
    _startHideControlsTimer();

    final dpadModeActive = InputModeController.instance.dpadModeActive;

    if (dpadModeActive) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        if (_isFullscreen) {
          _toggleFullscreen();
        } else {
          _exitTheater();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.contextMenu) {
        setState(() => _isSettingsOpen = !_isSettingsOpen);
        return KeyEventResult.handled;
      }

      // ── Deliberately NOT handled here: arrows, Select, gamepad A/B.
      // Returning `ignored` lets them bubble to the ambient Shortcuts
      // wired in app.dart, which turn arrows into DirectionalFocusIntent
      // and Select/A into ActivateIntent against whatever control is
      // actually focused. THIS is the fix — the previous version of this
      // method consumed every key unconditionally (even ones no branch
      // matched, via an unconditional `return handled` at the bottom),
      // which meant a D-Pad could never move focus at all inside the
      // theater screen, and pressing Select always triggered play/pause
      // instead of activating whatever was visibly focused. ──
      return KeyEventResult.ignored;
    }

    // ── Non-D-Pad (desktop keyboard / mouse) mode: keep the existing
    // power-user shortcuts exactly as they were. Arrow keys scrub/adjust
    // volume regardless of what has focus, since there's no on-screen focus
    // ring for a mouse user to navigate with in the first place. ──
    final isShift =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

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
      if (_isFullscreen) {
        _toggleFullscreen();
      } else {
        _exitTheater();
      }
    } else if (key == LogicalKeyboardKey.contextMenu) {
      setState(() => _isSettingsOpen = !_isSettingsOpen);
    } else {
      // Anything we don't recognize is left alone — this is the other half
      // of the same fix: previously this fell through to an unconditional
      // `return KeyEventResult.handled` regardless of whether any branch
      // above matched, silently eating keys like Tab too.
      return KeyEventResult.ignored;
    }

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

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await windowManager.setFullScreen(_isFullscreen);
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (_isFullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }

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
    _autoSkipController.dispose();
    _posSub?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();
    await _disposePlaybackResources();
    if (mounted) Navigator.pop(context);
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
    _autoSkipController.dispose();
    _posSub?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();

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
    final dpadModeActive = InputModeScope.of(context).dpadModeActive;

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
                  AnimatedOpacity(
                    opacity: _videoInitialized ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    // ── RepaintBoundary: the video texture updates on
                    // every decoded frame (dozens of times/sec) completely
                    // independently of the controls overlay above it
                    // (which only repaints on user interaction/position
                    // ticks). Without a boundary here, Flutter has no
                    // reason to treat them as separate compositor layers,
                    // so a control-bar repaint could force the video's
                    // layer to be re-recorded too, and vice versa. This
                    // pins the video to its own stable, GPU-cacheable
                    // layer. ──
                    child: RepaintBoundary(
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                        filterQuality: _getFilterQuality(),
                      ),
                    ),
                  ),

                  if (_videoInitialized)
                    AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        // ── One traversal group for the whole visible
                        // control surface. It doesn't unmount on hide (only
                        // opacity/IgnorePointer toggle), so whichever button
                        // or the seekbar had focus keeps it across a
                        // hide/show cycle — pressing D-Pad again after the
                        // bar fades back in resumes exactly where focus was
                        // left, it never resets to a default.
                        //
                        // RepaintBoundary: the Seekbar/timeline inside
                        // TheaterControls repaints several times a second
                        // during playback (see _PlaybackTimeline).
                        // Isolating the whole control surface onto its own
                        // layer means those ticks never force the Video
                        // layer above to re-record, and the video's own
                        // frequent texture updates never force this layer
                        // to repaint either. ──
                        child: RepaintBoundary(
                          child: FocusTraversalGroup(
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 24 + MediaQuery.paddingOf(context).top,
                                  left: 24,
                                  right: 24,
                                  child: GestureDetector(
                                    onTap: () {},
                                    child: TheaterTopBar(
                                      episode: widget.episode,
                                      uiPerformanceMode: _uiPerformanceMode,
                                      dpadModeActive: dpadModeActive,
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
                                      dpadModeActive: dpadModeActive,
                                      onToggleFullscreen: _toggleFullscreen,
                                      onInteract: _startHideControlsTimer,
                                      onToggleSettings: () => setState(
                                        () =>
                                            _isSettingsOpen = !_isSettingsOpen,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_isSettingsOpen)
                    Positioned(
                      bottom: 110,
                      right: 32,
                      child: TheaterSettingsMenu(
                        player: _player,
                        uiPerformanceMode: _uiPerformanceMode,
                        dpadModeActive: dpadModeActive,
                        onClose: () => setState(() => _isSettingsOpen = false),
                      ),
                    ),

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
                            dpadModeActive: dpadModeActive,
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
