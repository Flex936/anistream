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
import '../../core/settings/settings_scope.dart';
import '../../data/torrent/models/torrent.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/anilist/anilist_tracker_service.dart';
import '../../shared/widgets/toast.dart';
import 'services/streaming_controller_base.dart';
import 'services/streaming_controller.dart';
import 'services/remote_streaming_controller.dart';
import 'services/theater_data.dart';
import 'services/player_configurator.dart';
import 'services/auto_skip_controller.dart';
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
  WindowController? _ownWindowController;

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

    if (Platform.isLinux || Platform.isMacOS) {
      _registerPipReturnHandler();
    }
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

    // ── Hardware decoding + streaming tuning (shared with PIP window) ──
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
    _autoSkipController.dispose();
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
                  AnimatedOpacity(
                    opacity: _videoInitialized ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Video(
                      controller: _videoController,
                      controls: NoVideoControls,
                      filterQuality: _getFilterQuality(),
                    ),
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
                              top: 24 + MediaQuery.paddingOf(context).top,
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
