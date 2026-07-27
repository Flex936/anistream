import 'dart:async';
import 'dart:io' show Platform;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

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
      // ── initState can't be async — SystemChrome's setters return
      // Future<void>, so the fire-and-forget intent is made explicit
      // instead of silently dropped (unawaited_futures). ──
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
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

    // ── _initPlayerAndStream is Future<void> — initState can't be async,
    // so the fire-and-forget intent is made explicit (unawaited_futures).
    // The method itself already guards every `mounted`-sensitive step
    // internally. ──
    unawaited(_initPlayerAndStream());
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

    // ── Hardware decoding + streaming tuning. PlayerConfigurator is now
    // Future<void>-returning (see player_configurator.dart) rather than
    // firing six unawaited mpv property sets, so this is awaited. ──
    await PlayerConfigurator.configureForTheater(_player, s);

    // Preserves the original quirk: fullscreen is only forced here when
    // hwdec is left on "auto" and we're on a desktop platform (matches the
    // prior inline logic exactly).
    if (s.hardwareDecoding == 'auto' &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      await windowManager.setFullScreen(true);
    }

    // ── Restore persistent volume ─────────────────────────────────────────
    final savedVolume =
        await SharedPreferencesAsync().getDouble('theater_volume') ?? 100.0;
    await _player.setVolume(savedVolume);

    // ── Start streaming ───────────────────────────────────────────────────
    // Deliberately NOT awaited — StreamingController/RemoteStreamingController
    // report readiness asynchronously via notifyListeners as buffering
    // progresses, not by this returned Future completing. Awaiting it would
    // serialize AniList tracker init (below) behind it for no benefit, so
    // the fire-and-forget intent is made explicit instead. ──
    unawaited(
      _torrentController.initialize(
        widget.torrent.magnetLink,
        episodeNumber: widget.episode,
      ),
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
      // ── Listener callbacks (added via addListener) are synchronous —
      // Player.open/.play and the .then() chain below all return Futures
      // that can't be awaited here, so each fire-and-forget is wrapped
      // explicitly instead of silently dropped (unawaited_futures). ──
      unawaited(_player.open(Media(_torrentController.streamUrl!)));

      unawaited(
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
        }),
      );

      unawaited(_player.play());
    }
  }

  // ── Keyboard shortcuts (desktop) ──────────────────────────────────────────
  //
  // Previously all of this — plus the D-Pad mode arrow/select bubbling —
  // lived inside one Focus(autofocus: true, onKeyEvent: _handleKeyEvent)
  // wrapping the ENTIRE Scaffold. That Focus node claiming primaryFocus
  // with a screen-sized Rect was the actual bug: any DirectionalFocusIntent
  // triggered from it had a full-screen rectangle as its search anchor,
  // which is meaningless geometry for "find the nearest button in this
  // direction" — so D-Pad navigation inside the controls never worked
  // right, regardless of what individual controls did.
  //
  // CallbackShortcuts below replaces it for the desktop-keyboard case. It
  // does NOT claim focus and has no geometry of its own — it just
  // intercepts specific keys as they bubble up from whatever legitimately
  // has focus (or nothing, since these binidngs don't require an anchor
  // at all), which is exactly what a screen-wide "Space always
  // plays/pauses regardless of what's focused" convention needs, without
  // corrupting anything for D-Pad's own directional search.
  //
  // dpadModeActive itself is now PURELY a data signal read from
  // InputModeScope — not a focus mechanism — deciding which shortcut
  // scheme below is active. It has to stay: a desktop keyboard user
  // expects Left/Right/Up/Down to seek and adjust volume from anywhere,
  // exactly like any other video player; a D-Pad user needs those same
  // keys to move focus between controls instead. Both can't be true at
  // once on the same keys, so this is a real, unavoidable branch — not a
  // legacy holdover.
  Map<ShortcutActivator, VoidCallback> _buildShortcuts(bool dpadModeActive) {
    final subMenuOpen =
        _isSettingsOpen || _torrentController.needsManualSelection;

    final shortcuts = <ShortcutActivator, VoidCallback>{
      // ── Always active regardless of input mode or sub-menu state —
      // this is what actually closes a sub-menu, so it can't be gated
      // behind "no sub-menu open" the way the desktop shortcuts below
      // are. ──
      const SingleActivator(LogicalKeyboardKey.escape): _handleBackOrEscape,
      const SingleActivator(LogicalKeyboardKey.goBack): _handleBackOrEscape,
    };

    if (!dpadModeActive && !subMenuOpen) {
      shortcuts.addAll({
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.keyK): _togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _seekBackward,
        const SingleActivator(LogicalKeyboardKey.keyJ): _seekBackward,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _seekForward,
        const SingleActivator(LogicalKeyboardKey.keyL): _seekForward,
        const SingleActivator(LogicalKeyboardKey.arrowUp): _volumeUp,
        const SingleActivator(LogicalKeyboardKey.arrowDown): _volumeDown,
        const SingleActivator(LogicalKeyboardKey.keyF):
            _handleFullscreenShortcut,
        const SingleActivator(LogicalKeyboardKey.contextMenu):
            _toggleSettingsMenu,
      });
    }

    return shortcuts;
  }

  void _handleBackOrEscape() {
    _startHideControlsTimer();
    if (_isSettingsOpen) {
      setState(() => _isSettingsOpen = false);
      return;
    }
    if (_torrentController.needsManualSelection) {
      // ── Previously a dead end: the batch picker had no onBack wired at
      // all (BatchEpisodePickerOverlay only renders its own close button
      // `if (onBack != null)`, and this branch used to just set
      // _isSettingsOpen = false — already false here, since the picker
      // and settings menu are never open at the same time — so Escape
      // silently did nothing while the picker was showing). There was no
      // way to back out of a batch torrent without picking a file. Now
      // routes to the same exit used by the picker's own close button. ──
      unawaited(_exitTheater());
      return;
    }
    // maybePop() walks TheaterScreen's own PopScope below, which is where
    // the actual "exit fullscreen first, then exit Theater" decision is
    // made — kept in exactly one place rather than duplicated here.
    // Navigator.maybePop returns Future<bool>; this is a synchronous
    // shortcut callback, so the fire-and-forget intent is explicit.
    unawaited(Navigator.maybePop(context));
  }

  void _togglePlayPause() {
    _startHideControlsTimer();
    unawaited(_player.playOrPause());
  }

  void _seekBackward() {
    _startHideControlsTimer();
    final isShift =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    if (isShift && _chapters.isNotEmpty) {
      final prevChap = _chapters.lastWhere(
        (c) => c.start < _player.state.position - const Duration(seconds: 3),
        orElse: () => const Chapter(
          title: 'start',
          start: Duration.zero,
          end: Duration.zero,
        ),
      );
      unawaited(_player.seek(prevChap.start));
      return;
    }
    final target = _player.state.position - const Duration(seconds: 10);
    unawaited(_player.seek(target.isNegative ? Duration.zero : target));
  }

  void _seekForward() {
    _startHideControlsTimer();
    final isShift =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    if (isShift && _chapters.isNotEmpty) {
      final nextChap = _chapters.firstWhere(
        (c) => c.start > _player.state.position + const Duration(seconds: 1),
        orElse: () => Chapter(
          title: 'end',
          start: _player.state.duration,
          end: _player.state.duration,
        ),
      );
      unawaited(_player.seek(nextChap.start));
      return;
    }
    final target = _player.state.position + const Duration(seconds: 10);
    final duration = _player.state.duration;
    unawaited(_player.seek(target > duration ? duration : target));
  }

  void _volumeUp() {
    _startHideControlsTimer();
    final newVol = (_player.state.volume + 5).clamp(0.0, 100.0);
    unawaited(_player.setVolume(newVol));
    if (newVol > 0) {
      unawaited(SharedPreferencesAsync().setDouble('theater_volume', newVol));
    }
  }

  void _volumeDown() {
    _startHideControlsTimer();
    final newVol = (_player.state.volume - 5).clamp(0.0, 100.0);
    unawaited(_player.setVolume(newVol));
    if (newVol > 0) {
      unawaited(SharedPreferencesAsync().setDouble('theater_volume', newVol));
    }
  }

  void _handleFullscreenShortcut() {
    _startHideControlsTimer();
    unawaited(_toggleFullscreen());
  }

  void _toggleSettingsMenu() {
    _startHideControlsTimer();
    setState(() => _isSettingsOpen = !_isSettingsOpen);
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
      // ── Now awaited, matching _toggleFullscreen's existing pattern —
      // this method is already async, so there's no reason these two
      // calls were left unawaited while the identical pair in
      // _toggleFullscreen was correctly awaited. ──
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
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
    await _posSub?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();
    await _disposePlaybackResources();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      // ── dispose() must stay synchronous (it can't become async — the
      // required super.dispose() call has to happen in this same
      // synchronous frame), so these fire-and-forget calls are wrapped
      // explicitly instead of silently dropped (unawaited_futures). ──
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }

    _hideControlsTimer?.cancel();
    _autoSkipController.dispose();
    final posSub = _posSub;
    if (posSub != null) {
      unawaited(posSub.cancel());
    }
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();

    if (!_isClosing) {
      _isClosing = true;
      unawaited(Future.microtask(_disposePlaybackResources));
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

    return PopScope(
      // ── Never let a bare pop through directly — both branches below
      // always explicitly handle it (exit fullscreen and stay, or run
      // _exitTheater's careful async teardown sequence before popping).
      // This is what maybePop() — called from _handleBackOrEscape above,
      // AND from Dpad.wrap()'s root-level onBack via the same
      // Navigator.maybePop() path — actually resolves to. One
      // mechanism, reachable from the system back gesture, a desktop
      // Escape key, and the D-Pad remote's dedicated Back key alike. ──
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_isFullscreen) {
          unawaited(_toggleFullscreen());
        } else {
          unawaited(_exitTheater());
        }
      },
      child: CallbackShortcuts(
        bindings: _buildShortcuts(dpadModeActive),
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
                    unawaited(_player.playOrPause());
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
                          // ── ExcludeFocus alongside IgnorePointer: the
                          // opacity/IgnorePointer pair alone only ever
                          // blocked POINTER hit-testing when controls were
                          // hidden — keyboard/D-Pad focus could still land
                          // on (and stay on) a fully invisible button.
                          // ExcludeFocus removes the whole subtree from the
                          // focus tree entirely while excluding is true, so
                          // hidden controls are genuinely unreachable, not
                          // just untappable. Flutter moves focus elsewhere
                          // automatically if something inside was focused
                          // right as this flips. ──
                          child: ExcludeFocus(
                            excluding: !_showControls,
                            child: RepaintBoundary(
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 24 + MediaQuery.paddingOf(context).top,
                                    left: 24,
                                    right: 24,
                                    // ── DpadRegion: its own visual section,
                                    // separate from the controls bar below.
                                    // No edge-behavior overrides — default
                                    // leave/leave lets Down escape into the
                                    // controls region, and Up has nothing
                                    // above it to find anyway. ──
                                    child: DpadRegion(
                                      memoryKey: 'theater.topbar',
                                      child: GestureDetector(
                                        onTap: () {},
                                        child: TheaterTopBar(
                                          episode: widget.episode,
                                          uiPerformanceMode: _uiPerformanceMode,
                                          onBack: _exitTheater,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: DpadRegion(
                                      memoryKey: 'theater.controls',
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
                                            () => _isSettingsOpen =
                                                !_isSettingsOpen,
                                          ),
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
                          onClose: () =>
                              setState(() => _isSettingsOpen = false),
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
                              // ── Previously never wired — the picker's
                              // own close (X) button only renders `if
                              // (onBack != null)`, so it never appeared at
                              // all. Exits Theater entirely, matching what
                              // Escape now does in the same state (see
                              // _handleBackOrEscape) — there's no partial
                              // "fullscreen exit" to do here since no
                              // stream has started yet. ──
                              onBack: _exitTheater,
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
      ),
    );
  }
}
