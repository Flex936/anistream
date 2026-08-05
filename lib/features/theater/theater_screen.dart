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
import 'services/controls_visibility_controller.dart';
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
  late final ControlsVisibilityController _controlsVisibility;

  bool _videoInitialized = false;
  bool _isSettingsOpen = false;
  bool _isFullscreen = true;
  bool _isClosing = false;

  // ── Set by TheaterControls/Seekbar/the volume Slider via
  // onSeekbarFocusChange/onVolumeFocusChange — read only by _onKeyEvent
  // below, never by build(), so plain field writes (no setState) are
  // correct and cheap. See _onKeyEvent's doc comment for why these exist. ──
  bool _seekbarFocused = false;
  bool _volumeSliderFocused = false;

  // ── Auto-skip setting (the state machine itself now lives in
  // AutoSkipController) ──
  bool _autoSkip = false;

  // ── Performance settings ─────────────────────────────────────────────────
  bool _uiPerformanceMode = false;
  String _videoFilterQuality = 'low';

  List<Chapter> _chapters = [];
  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(libass: true));
    const videoConfig = VideoControllerConfiguration(
      androidAttachSurfaceAfterVideoParameters: true,
    );
    _videoController = VideoController(_player, configuration: videoConfig);

    _controlsVisibility = ControlsVisibilityController(
      player: _player,
      isSubMenuOpen: () => _isSettingsOpen,
    );

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
    _controlsVisibility.registerActivity();

    // ── Registered last, after every field this handler can read is
    // already initialized — see _onKeyEvent's doc comment. ──
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
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

  // ── Platform ───────────────────────────────────────────────────────────
  //
  // Desktop-only flag, threaded into TheaterControls so it can hide the
  // fullscreen toggle on Mobile/TV per DESIGN.md § 3 ("Hide PC-specific UI
  // controls ... on Mobile/TV builds"). Mirrors the exact platform test
  // already used elsewhere in this file (_initPlayerAndStream,
  // _toggleFullscreen, _disposePlaybackResources) rather than introducing
  // a new check.
  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // ── Keyboard shortcuts (desktop) ──────────────────────────────────────────
  //
  // Registered directly with HardwareKeyboard.instance rather than via
  // CallbackShortcuts (the previous approach). CallbackShortcuts only
  // intercepts key events that BUBBLE UP the focus chain from whatever
  // widget currently holds primary focus — it is not a global listener.
  // The play button was the only autofocus: true target in the controls
  // subtree, autofocus only fires once on first mount, and the controls
  // subtree is wrapped in ExcludeFocus(excluding: !showControls): the very
  // first time controls auto-hide, ExcludeFocus(excluding: true) forcibly
  // clears focus from whatever was inside it, and nothing ever re-requests
  // it afterward. From that point on, primary focus is permanently
  // unparented — CallbackShortcuts has nothing to bubble from, so EVERY
  // shortcut (including Escape) went dark for the rest of the session,
  // matching the reported "only works while a control is highlighted."
  //
  // A raw HardwareKeyboard handler receives every key event regardless of
  // what currently has focus, so ExcludeFocus clearing the play button's
  // focus is no longer relevant to whether shortcuts keep working.
  //
  // This bypasses the focus-tree's own bubbling/consumption semantics
  // entirely, though — unlike CallbackShortcuts, this handler does NOT
  // automatically defer to a widget that already handled the same key via
  // its own Focus.onKeyEvent (Seekbar and the volume Slider both do this
  // for Left/Right when they hold keyboard focus). Left unguarded, that
  // would double-seek (Seekbar) or seek unexpectedly while the user is
  // nudging volume (the Slider). _seekbarFocused/_volumeSliderFocused
  // (set via TheaterControls' onSeekbarFocusChange/onVolumeFocusChange)
  // exist specifically so the literal ArrowLeft/ArrowRight/ArrowUp/
  // ArrowDown cases below can defer to that widget's own handling instead.
  // The J/K/L letter-key equivalents are unaffected by this guard — Seekbar
  // and the Slider only ever bind the literal arrow keys locally, never
  // letters, so those always reach this handler regardless of focus.
  //
  // dpadModeActive remains a pure data signal (not a focus mechanism)
  // deciding which shortcut scheme is active: a desktop keyboard user
  // expects Left/Right/Up/Down to seek/adjust volume from anywhere, a
  // D-Pad user needs those same keys to move focus between controls
  // instead — both can't be true on the same keys, so this branch stays.
  bool _onKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;

    // ── Always active regardless of input mode or sub-menu state — this
    // is what actually closes a sub-menu, so it can't be gated behind "no
    // sub-menu open" the way the desktop-only bindings below are. ──
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _handleBackOrEscape();
      return true;
    }

    final dpadModeActive = InputModeScope.of(
      context,
      listen: false,
    ).dpadModeActive;
    final subMenuOpen =
        _isSettingsOpen || _torrentController.needsManualSelection;
    if (dpadModeActive || subMenuOpen) return false;

    switch (key) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        _togglePlayPause();
        return true;

      case LogicalKeyboardKey.keyJ:
        _seekBackward();
        return true;
      case LogicalKeyboardKey.arrowLeft:
        if (_seekbarFocused || _volumeSliderFocused) return false;
        _seekBackward();
        return true;

      case LogicalKeyboardKey.keyL:
        _seekForward();
        return true;
      case LogicalKeyboardKey.arrowRight:
        if (_seekbarFocused || _volumeSliderFocused) return false;
        _seekForward();
        return true;

      case LogicalKeyboardKey.arrowUp:
        if (_volumeSliderFocused) return false;
        _volumeUp();
        return true;
      case LogicalKeyboardKey.arrowDown:
        if (_volumeSliderFocused) return false;
        _volumeDown();
        return true;

      case LogicalKeyboardKey.keyF:
        _handleFullscreenShortcut();
        return true;
      case LogicalKeyboardKey.contextMenu:
        _toggleSettingsMenu();
        return true;
    }
    return false;
  }

  void _handleBackOrEscape() {
    _controlsVisibility.registerActivity();
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
    _controlsVisibility.registerActivity();
    unawaited(_player.playOrPause());
  }

  void _seekBackward() {
    _controlsVisibility.registerActivity();
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
    _controlsVisibility.registerActivity();
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
    _controlsVisibility.registerActivity();
    final newVol = (_player.state.volume + 5).clamp(0.0, 100.0);
    unawaited(_player.setVolume(newVol));
    if (newVol > 0) {
      unawaited(SharedPreferencesAsync().setDouble('theater_volume', newVol));
    }
  }

  void _volumeDown() {
    _controlsVisibility.registerActivity();
    final newVol = (_player.state.volume - 5).clamp(0.0, 100.0);
    unawaited(_player.setVolume(newVol));
    if (newVol > 0) {
      unawaited(SharedPreferencesAsync().setDouble('theater_volume', newVol));
    }
  }

  void _handleFullscreenShortcut() {
    _controlsVisibility.registerActivity();
    unawaited(_toggleFullscreen());
  }

  void _toggleSettingsMenu() {
    _controlsVisibility.registerActivity();
    setState(() => _isSettingsOpen = !_isSettingsOpen);
  }

  // ── Background gesture ────────────────────────────────────────────────

  void _handleBackgroundTap() {
    if (_isSettingsOpen) {
      setState(() => _isSettingsOpen = false);
      _controlsVisibility.registerActivity();
      return;
    }
    if (_controlsVisibility.visible.value) {
      _controlsVisibility.hideNow();
    } else {
      _controlsVisibility.registerActivity();
    }
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
    _autoSkipController.dispose();
    await _posSub?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();
    await _disposePlaybackResources();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);

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

    _controlsVisibility.dispose();
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

  // ── Controls overlay (top bar + control bar) ────────────────────────────
  //
  // Parameterized on showControls/dpadModeActive rather than reading
  // fields directly, since it's built from inside the ValueListenableBuilder
  // in build() below — see that method's doc comment for why.
  Widget _buildControlsOverlay(bool showControls, bool dpadModeActive) {
    return AnimatedOpacity(
      opacity: showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !showControls,
        // ── ExcludeFocus alongside IgnorePointer: the opacity/
        // IgnorePointer pair alone only ever blocked POINTER hit-testing
        // when controls were hidden — keyboard/D-Pad focus could still
        // land on (and stay on) a fully invisible button. ExcludeFocus
        // removes the whole subtree from the focus tree entirely while
        // excluding is true, so hidden controls are genuinely
        // unreachable, not just untappable. Flutter moves focus elsewhere
        // automatically if something inside was focused right as this
        // flips — which is exactly the mechanism that used to orphan
        // primary focus and break CallbackShortcuts (see _onKeyEvent's
        // doc comment); the global handler no longer depends on where
        // focus ends up after that, so this stays exactly as it was. ──
        child: ExcludeFocus(
          excluding: !showControls,
          child: RepaintBoundary(
            child: Stack(
              children: [
                Positioned(
                  top: 24 + MediaQuery.paddingOf(context).top,
                  left: 24,
                  right: 24,
                  // ── DpadRegion: its own visual section, separate from
                  // the controls bar below. No edge-behavior overrides —
                  // default leave/leave lets Down escape into the
                  // controls region, and Up has nothing above it to find
                  // anyway. The GestureDetector(onTap: () {}) wrapper that
                  // used to sit here has been removed — it existed only
                  // to swallow taps, and TheaterTopBar's own row paints
                  // nothing behind its two children, so it was never
                  // actually needed here in the first place; its real
                  // job was swallowing taps meant for TheaterControls'
                  // gradient background below, which is fixed by removing
                  // ITS wrapper instead (see the DpadRegion below). ──
                  child: DpadRegion(
                    memoryKey: 'theater.topbar',
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
                  // ── The no-op GestureDetector(onTap: () {}) that used
                  // to wrap TheaterControls here is gone. It existed to
                  // "swallow" background taps within the control bar, but
                  // TheaterControls' gradient Container paints across
                  // nearly its entire bounds, so under the OLD default
                  // (deferToChild) hit-test behavior this wrapper
                  // absorbed EVERY tap that landed anywhere on that
                  // gradient — including taps that weren't on an actual
                  // button — before they could ever reach the root
                  // GestureDetector's onTap. That's the direct cause of
                  // "only the right screen region registers correctly":
                  // real buttons still worked (a descendant's own tap
                  // recognizer correctly wins the gesture arena over an
                  // ancestor's, by Flutter's standard nested-
                  // GestureDetector resolution — innermost recognizer
                  // gets first chance to accept), but empty gradient
                  // space did nothing instead of toggling visibility.
                  // Removing this wrapper lets those empty-space taps
                  // correctly fall through to the root's onTap
                  // (_handleBackgroundTap) while real buttons keep
                  // working exactly as before. ──
                  child: DpadRegion(
                    memoryKey: 'theater.controls',
                    child: TheaterControls(
                      player: _player,
                      chapterMetadata: _chapters,
                      isSettingsOpen: _isSettingsOpen,
                      isFullscreen: _isFullscreen,
                      isDesktop: _isDesktopPlatform,
                      uiPerformanceMode: _uiPerformanceMode,
                      dpadModeActive: dpadModeActive,
                      onToggleFullscreen: _toggleFullscreen,
                      onInteract: _controlsVisibility.registerActivity,
                      onInteractionStart: _controlsVisibility.beginInteraction,
                      onInteractionEnd: _controlsVisibility.endInteraction,
                      onToggleSettings: () =>
                          setState(() => _isSettingsOpen = !_isSettingsOpen),
                      onSeekbarFocusChange: (f) => _seekbarFocused = f,
                      onVolumeFocusChange: (f) => _volumeSliderFocused = f,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dpadModeActive = InputModeScope.of(context).dpadModeActive;

    // ── The video texture, the settings-menu popup, and the loading/
    // batch-picker overlay switcher don't depend on controls visibility
    // at all — computed once per real setState() (video-ready, settings
    // toggle, chapters loaded, etc.), exactly as before. Passed as the
    // `child` of the ValueListenableBuilder below so it's reused, not
    // rebuilt, on every controls-visibility transition. ──
    final staticLayer = Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _videoInitialized ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          // ── RepaintBoundary: the video texture updates on every
          // decoded frame (dozens of times/sec) completely independently
          // of the controls overlay above it (which only repaints on
          // user interaction/position ticks). Without a boundary here,
          // Flutter has no reason to treat them as separate compositor
          // layers, so a control-bar repaint could force the video's
          // layer to be re-recorded too, and vice versa. This pins the
          // video to its own stable, GPU-cacheable layer. ──
          child: RepaintBoundary(
            child: Video(
              controller: _videoController,
              // ── NoVideoControls is media_kit_video's `const dynamic`
              // sentinel for "no controls builder" — its actual runtime
              // value is `null`, not a function. The parameter itself is
              // nullable (VideoControlsBuilder?), so the cast target
              // must be nullable too, or casting null throws at runtime
              // (confirmed via crash log: "type 'Null' is not a subtype
              // of type '(VideoState) => Widget' in type cast"). ──
              controls: NoVideoControls as Widget Function(VideoState)?,
              filterQuality: _getFilterQuality(),
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
                  // ── Previously never wired — the picker's own close
                  // (X) button only renders `if (onBack != null)`, so it
                  // never appeared at all. Exits Theater entirely,
                  // matching what Escape now does in the same state (see
                  // _handleBackOrEscape) — there's no partial "fullscreen
                  // exit" to do here since no stream has started yet. ──
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
    );

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
      child: Scaffold(
        backgroundColor: AppPalette.black,
        body: ExcludeSemantics(
          // ── ValueListenableBuilder scoped to controls visibility only
          // — MouseRegion's cursor and the controls overlay's opacity/
          // hit-testing both depend on it, but `staticLayer` above (video,
          // settings menu, loading/batch-picker overlay) does not, and is
          // passed as `child` so it's reused rather than reconstructed on
          // every show/hide transition. This is what actually fixes the
          // rebuild-storm half of the auto-hide bug: MouseRegion.onHover
          // used to call setState() on this whole State directly, forcing
          // the entire screen (video included) to rebuild on every single
          // pointer-move tick while the mouse was moving. registerActivity()
          // now just writes to a ValueNotifier, which only notifies
          // listeners on a genuine true→false/false→true transition — so
          // hovering with controls already visible costs a cancelled+
          // rescheduled Timer, not a rebuild of anything visual. ──
          child: ValueListenableBuilder<bool>(
            valueListenable: _controlsVisibility.visible,
            child: staticLayer,
            builder: (context, showControls, child) {
              return MouseRegion(
                cursor: showControls
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.none,
                onHover: (_) => _controlsVisibility.registerActivity(),
                // ── opaque (not the default deferToChild): guarantees a
                // tap anywhere in this Stack — including areas where
                // nothing paints, like gaps around the IgnorePointer'd
                // controls overlay while it's hidden — reaches this
                // detector's own onTap. Real interactive descendants
                // (buttons, the settings menu's close button, etc.) are
                // unaffected: a descendant's own tap recognizer still
                // wins the gesture arena over this ancestor's, by
                // Flutter's standard nested-GestureDetector resolution —
                // opaque only changes whether EMPTY space counts as a
                // hit, not how competing recognizers along the same
                // hit-test chain resolve against each other. ──
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleBackgroundTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child!,
                      if (_videoInitialized)
                        _buildControlsOverlay(showControls, dpadModeActive),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
