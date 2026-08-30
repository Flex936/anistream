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
import '../../core/settings/settings_service.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_tracker_service.dart';
import '../../data/anilist/models/anime.dart';
import 'services/auto_skip_controller.dart';
import 'services/controls_visibility_controller.dart';
import 'services/playback_diagnostics.dart';
import 'services/playback_stall_controller.dart';
import 'services/player_configurator.dart';
import 'services/remote_streaming_controller.dart';
import 'services/streaming_controller.dart';
import 'services/streaming_controller_base.dart';
import 'services/theater_data.dart';
import 'widgets/batch_picker.dart';
import 'widgets/playback_stall_indicator.dart';
import 'widgets/theater_controls.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_settings.dart';

/// Returned by [TheaterScreen] when the user taps its freeze-recovery
/// restart button, or toggles Libass in [TheaterSettingsMenu] (see
/// [_TheaterScreenState._handleRestartRequested] /
/// [_TheaterScreenState._handleLibassToggle]). Carries the still-live,
/// still-buffered streaming session across to whatever [TheaterScreen]
/// instance replaces this one, so either path recovers/reconfigures
/// near-instantly instead of re-downloading the torrent from scratch. A
/// normal exit pops with `null` instead — see
/// [_TheaterScreenState._exitTheater].
class TheaterRestartRequest {
  final BaseStreamingController resumeController;
  final Duration resumePosition;

  const TheaterRestartRequest({
    required this.resumeController,
    required this.resumePosition,
  });
}

/// Carries the message/icon/color for Theater's own in-flow status toast
/// — see [TheaterTopNotification]'s doc comment
/// (widgets/theater_player.dart) for how this is rendered.
class _TopNotification {
  final String message;
  final IconData icon;
  final Color iconColor;

  const _TopNotification({
    required this.message,
    required this.icon,
    required this.iconColor,
  });
}

class TheaterScreen extends StatefulWidget {
  /// AniList context for progress tracking — always null together with
  /// [episode] for a custom-magnet stream with no anime metadata behind
  /// it (see [magnetUri]). Never null on the normal from-AnimeDetails
  /// path.
  final Anime? anime;

  /// Paired with [anime] — see that field's doc comment. Also used as
  /// [RemoteStreamingController]/[StreamingController]'s batch-file
  /// auto-match hint when non-null.
  final int? episode;

  /// The magnet link to stream — the one piece of state every session
  /// needs regardless of whether it came from a scored `Torrent` search
  /// result (`torrent.magnetLink`) or a user-pasted custom magnet link.
  final String magnetUri;

  /// Shown in the top bar / loading overlay in place of "Episode N" when
  /// [episode] is null. Ignored otherwise.
  final String? displayTitle;

  /// Non-null only when this screen is replacing a prior instance after
  /// a freeze-recovery restart or a Libass toggle — the already-buffered
  /// controller to resume from instead of starting a fresh torrent
  /// download. Always paired with [resumePosition].
  final BaseStreamingController? resumeController;

  /// Paired with [resumeController] — where to seek to once the resumed
  /// stream reopens. Always null on a normal (non-restart) entry.
  final Duration? resumePosition;

  const TheaterScreen({
    super.key,
    this.anime,
    this.episode,
    required this.magnetUri,
    this.displayTitle,
    this.resumeController,
    this.resumePosition,
  }) : assert(
         (resumeController == null) == (resumePosition == null),
         'resumeController and resumePosition must both be null or both be provided',
       ),
       assert(
         (anime == null) == (episode == null),
         'anime and episode must both be null (custom magnet stream) or both be provided',
       );

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

  // Read-only diagnostic instrumentation for the mpv paused-freeze bug —
  // see playback_diagnostics.dart's class doc. Never affects playback
  // behavior.
  late final PlaybackDiagnostics _playbackDiagnostics;

  // Drives the mid-playback "Buffering…" indicator off mpv's own
  // buffering signal — see playback_stall_controller.dart's class doc.
  late final PlaybackStallController _playbackStallController;

  /// A same-position pause before a manual restart, below which a
  /// restart wouldn't meaningfully rewind anything.
  static const Duration _kFreezeRecoveryRewind = Duration(seconds: 5);

  /// Fixed-duration manual seek for OP/ED skipping — Ctrl+→ on desktop
  /// (see _onKeyEvent), or the dedicated skip button in TheaterControls
  /// on Mobile/TV. Deliberately independent of chapter metadata (unlike
  /// AutoSkipController's own chapter-driven auto-skip): this always
  /// seeks exactly 90 seconds forward, regardless of whether an OP/ED
  /// chapter boundary happens to sit nearby. No backward equivalent —
  /// only a forward skip was asked for.
  static const Duration _kExactSkipDuration = Duration(minutes: 1, seconds: 30);

  bool _videoInitialized = false;
  bool _isSettingsOpen = false;
  bool _isFullscreen = true;
  bool _isClosing = false;

  // Set by TheaterControls/Seekbar/the volume Slider via
  // onSeekbarFocusChange/onVolumeFocusChange. Read only by _onKeyEvent
  // below, never by build(), so plain field writes (no setState) are
  // correct and cheap. See _onKeyEvent's doc comment for why these exist.
  bool _seekbarFocused = false;
  bool _volumeSliderFocused = false;

  // Auto-skip setting; the state machine itself lives in
  // AutoSkipController.
  bool _autoSkip = false;

  // Gates the freeze-recovery restart button in TheaterTopBar. Defaults
  // false — see AppSettings.showFreezeRecoveryButton's doc comment for
  // why this stays a manual, opt-in action rather than an automatic one.
  bool _showFreezeRecoveryButton = false;

  // Performance settings.
  bool _uiPerformanceMode = false;
  String _videoFilterQuality = 'low';

  /// What `_player` was actually constructed with — read once in
  /// initState (see below) purely so TheaterSettingsMenu has a current
  /// value to show its toggle in. `_handleLibassToggle` is what changes
  /// the underlying setting; this field never mutates on its own once
  /// this screen instance exists.
  late bool _libassEnabled;

  List<Chapter> _chapters = [];
  StreamSubscription<Duration>? _posSub;

  // Theater's own in-flow status toast (AniList sync confirmation,
  // auto-skip arming) — see TheaterTopNotification's doc comment
  // (widgets/theater_player.dart) for why this renders as plain State/
  // Positioned content in this screen's own Stack rather than through an
  // Overlay-based toast.
  _TopNotification? _topNotification;
  Timer? _topNotificationTimer;
  static const Duration _kTopNotificationDuration = Duration(seconds: 4);

  // Vertical clearance TheaterTopNotification reserves below
  // TheaterTopBar's own top offset (see _buildControlsOverlay), so the
  // notification never visually overlaps the back button regardless of
  // whether the controls overlay is currently shown or hidden.
  static const double _kTopBarClearance = 64.0;

  /// "Episode N" when this session has AniList episode context, or
  /// [TheaterScreen.displayTitle] (falling back to "Custom Stream")
  /// otherwise — shown in [TheaterTopBar] and [TheaterLoadingOverlay] in
  /// place of duplicating this branch in each of those dumb widgets.
  String get _displayLabel => widget.episode != null
      ? 'Episode ${widget.episode}'
      : (widget.displayTitle ?? 'Custom Stream');

  @override
  void initState() {
    super.initState();

    // `getInheritedWidgetOfExactType` (the `listen: false` path
    // SettingsScope.of uses) is a plain, non-establishing ancestor
    // lookup — safe here even though initState runs before this
    // element's own first build, unlike `dependOnInheritedWidgetOfExactType`
    // (a listening read), which Flutter reserves for didChangeDependencies.
    // Read directly off SettingsScope rather than the no-BuildContext
    // SettingsCache mirror: this widget has a perfectly good
    // BuildContext, and ARCHITECTURE.md § 3 is explicit that
    // SettingsCache exists only for services that don't.
    _libassEnabled = SettingsScope.of(
      context,
      listen: false,
    ).settings.libassEnabled;

    // media_kit's PlayerConfiguration.libass is only ever read at
    // construction time — there's no exposed way to flip it on an
    // already-running Player — so a later change to this setting goes
    // through _handleLibassToggle's full restart instead of a live
    // property mutation.
    _player = Player(
      configuration: PlayerConfiguration(libass: _libassEnabled),
    );
    const videoConfig = VideoControllerConfiguration(
      androidAttachSurfaceAfterVideoParameters: true,
    );
    _videoController = VideoController(_player, configuration: videoConfig);

    _controlsVisibility = ControlsVisibilityController(
      player: _player,
      isSubMenuOpen: () => _isSettingsOpen,
    );
    _playbackDiagnostics = PlaybackDiagnostics(player: _player);
    _playbackStallController = PlaybackStallController(player: _player);

    if (Platform.isAndroid || Platform.isIOS) {
      // initState can't be async — SystemChrome's setters return
      // Future<void>, so the fire-and-forget intent is made explicit
      // instead of silently dropped (unawaited_futures).
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
      onSkipArmed: (skipLabel) => _showTopNotification(
        message: 'Auto-skipping $skipLabel in 2s...',
        icon: Icons.fast_forward_rounded,
        iconColor: AppPalette.primary,
      ),
    );

    _tracker = AnilistTrackerService(
      onSuccess: () => _showTopNotification(
        message: 'Progress saved to AniList',
        icon: Icons.check_circle_rounded,
        iconColor: AppPalette.statusReleasing,
      ),
      onFailure: (message) => _showTopNotification(
        message: message,
        icon: Icons.error_outline_rounded,
        iconColor: AppPalette.statusCancelled,
      ),
    );

    // _initPlayerAndStream is Future<void> — initState can't be async,
    // so the fire-and-forget intent is made explicit (unawaited_futures).
    // The method itself already guards every `mounted`-sensitive step
    // internally.
    unawaited(_initPlayerAndStream());
    _controlsVisibility.registerActivity();

    // Registered last, after every field this handler can read is
    // already initialized — see _onKeyEvent's doc comment.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  Future<void> _initPlayerAndStream() async {
    if (!mounted) return;

    final s = SettingsScope.of(context, listen: false).settings;

    setState(() {
      _uiPerformanceMode = s.uiPerformanceMode;
      _videoFilterQuality = s.videoFilterQuality;
      _autoSkip = s.autoSkip;
      _showFreezeRecoveryButton = s.showFreezeRecoveryButton;
    });

    final bool isResuming = widget.resumeController != null;

    final BaseStreamingController newController =
        widget.resumeController ??
        (s.serverMode && s.serverUrl.isNotEmpty
            ? RemoteStreamingController(serverUrl: s.serverUrl)
            : StreamingController());
    newController.addListener(_onTorrentStateChanged);

    if (!mounted) {
      // Only disposes a controller this method constructed itself — a
      // resumed controller is a still-live session handed off by a
      // prior TheaterScreen instance, not this screen's to discard on a
      // mount-race edge case.
      if (!isResuming) newController.dispose();
      return;
    }

    final oldPlaceholder = _torrentController;
    setState(() => _torrentController = newController);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => oldPlaceholder.dispose(),
    );

    // Hardware decoding + streaming tuning is awaited here, since
    // PlayerConfigurator.configureForTheater returns Future<void> (see
    // player_configurator.dart).
    await PlayerConfigurator.configureForTheater(_player, s);

    // Fullscreen is only forced here when hwdec is left on "auto" and
    // the app is running on a desktop platform.
    if (s.hardwareDecoding == 'auto' &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      await windowManager.setFullScreen(true);
    }

    // Restores persistent volume.
    final savedVolume =
        await SharedPreferencesAsync().getDouble('theater_volume') ?? 100.0;
    await _player.setVolume(savedVolume);

    if (isResuming) {
      // The controller is already buffered and ready — its readiness
      // notification already fired on the TheaterScreen instance this
      // one is replacing, so a freshly attached listener here won't
      // replay it. Readiness is checked directly instead, running the
      // same open/seek/play bootstrap _onTorrentStateChanged runs for a
      // first-time stream.
      _onTorrentStateChanged();
    } else {
      // Starts streaming. Deliberately not awaited — StreamingController/
      // RemoteStreamingController report readiness asynchronously via
      // notifyListeners as buffering progresses, not by this returned
      // Future completing. Awaiting it would serialize AniList tracker
      // init (below) behind it for no benefit, so the fire-and-forget
      // intent is made explicit instead.
      unawaited(
        _torrentController.initialize(
          widget.magnetUri,
          episodeNumber: widget.episode,
        ),
      );
    }

    // AniList progress tracking — skipped entirely for a custom-magnet
    // session with no anime/episode context. AnilistTrackerService stays
    // in its default logged-out, ineligible state until init() runs, so
    // updateProgress() below is already a safe no-op in that case.
    final trackedAnime = widget.anime;
    final trackedEpisode = widget.episode;
    if (trackedAnime != null && trackedEpisode != null) {
      await _tracker.init(
        mediaId: trackedAnime.id,
        episode: trackedEpisode,
        totalEpisodes: trackedAnime.episodes,
      );
    }
    if (!mounted) return;

    _posSub = _player.stream.position.listen((pos) {
      _tracker.updateProgress(pos, _player.state.duration);
      _autoSkipController.onPosition(pos);
    });
  }

  // Controller listener.

  void _onTorrentStateChanged() {
    // Defensive guard alongside removing this listener as the first
    // statement in _exitTheater/_teardownForRestart below — a stray
    // notifyListeners() landing in either method's own teardown sequence
    // (a trailing FFI callback, a last remote-poll tick) should never be
    // able to reopen or replay against a Player that's already being
    // stopped and disposed.
    if (_isClosing) return;
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      setState(() => _videoInitialized = true);
      // Listener callbacks (added via addListener) are synchronous —
      // Player.open and the .then() chains below all return Futures
      // that can't be awaited here, so each fire-and-forget is wrapped
      // explicitly instead of silently dropped (unawaited_futures).
      unawaited(_player.open(Media(_torrentController.streamUrl!)));

      final resumePosition = widget.resumePosition;
      if (resumePosition != null) {
        // Player.open()'s Future completes once mpv accepts the open
        // command, not once the file has actually finished loading — a
        // seek issued immediately after races the load and gets
        // silently dropped/overridden back to 0:00. Waiting for a
        // genuine duration (the same signal the chapter-load below
        // already relies on) confirms the file is actually ready to
        // accept a seek before issuing one. play() is deliberately
        // deferred until after the seek lands too, so a restart (freeze
        // recovery or a Libass toggle) jumps straight to the resume
        // position instead of briefly showing frame 0 first — this only
        // affects the restart path; the normal first-time-watching path
        // below still plays immediately, since it never needs to seek at
        // all.
        unawaited(
          _player.stream.duration.firstWhere((d) => d > Duration.zero).then((
            _,
          ) async {
            await _player.seek(resumePosition);
            await _player.play();
          }),
        );
      } else {
        unawaited(_player.play());
      }

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
    }
  }

  // Top notification.

  void _showTopNotification({
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    if (!mounted) return;
    _topNotificationTimer?.cancel();
    setState(() {
      _topNotification = _TopNotification(
        message: message,
        icon: icon,
        iconColor: iconColor,
      );
    });
    _topNotificationTimer = Timer(_kTopNotificationDuration, () {
      if (mounted) setState(() => _topNotification = null);
    });
  }

  // Platform.
  //
  // Desktop-only flag, threaded into TheaterControls so it can hide the
  // fullscreen toggle on Mobile/TV per DESIGN.md § 3 ("Hide PC-specific UI
  // controls ... on Mobile/TV builds"). Mirrors the exact platform test
  // already used elsewhere in this file (_initPlayerAndStream,
  // _toggleFullscreen, _disposePlaybackResources) rather than introducing
  // a new check.
  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// True while either physical Ctrl key is held — backs the Ctrl+→
  /// exact-skip shortcut below. Desktop-only in practice: TV/mobile never
  /// reach this file's raw HardwareKeyboard handler for a Ctrl chord in
  /// the first place, since neither platform has a Ctrl key to hold.
  bool get _isCtrlPressed =>
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.controlLeft,
      ) ||
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.controlRight,
      );

  // Keyboard shortcuts (desktop).
  //
  // Registered directly with HardwareKeyboard.instance rather than via
  // CallbackShortcuts. A raw HardwareKeyboard handler receives every key
  // event regardless of what currently holds focus, which matters here
  // because the controls subtree sits inside an `ExcludeFocus` that's
  // toggled on auto-hide — a focus-chain-bubbling approach would stop
  // receiving events once nothing in that subtree can hold focus anymore.
  //
  // This bypasses the focus tree's own bubbling/consumption semantics
  // entirely, so unlike a focus-chain-based dispatcher, this handler does
  // NOT automatically defer to a widget that already handled the same key
  // via its own `Focus.onKeyEvent` (Seekbar and the volume Slider both do
  // this for Left/Right when they hold keyboard focus). Left unguarded,
  // that would double-seek (Seekbar) or seek unexpectedly while the user
  // is nudging volume (the Slider). `_seekbarFocused`/`_volumeSliderFocused`
  // (set via TheaterControls' onSeekbarFocusChange/onVolumeFocusChange)
  // exist specifically so the literal ArrowLeft/ArrowRight/ArrowUp/
  // ArrowDown cases below can defer to that widget's own handling instead.
  // The J/K/L letter-key equivalents are unaffected by this guard —
  // Seekbar and the Slider only ever bind the literal arrow keys locally,
  // never letters, so those always reach this handler regardless of focus.
  //
  // Ctrl+→ (exact-skip) is the one arrow-key case that does NOT defer to
  // _seekbarFocused/_volumeSliderFocused: Seekbar's own onKeyEvent
  // (seekbar.dart) explicitly ignores Left/Right whenever Ctrl is held,
  // rather than performing its own ±10s seek, so there's nothing to defer
  // to there. The volume Slider's internal keyboard Shortcuts bind a
  // plain (non-Ctrl) SingleActivator for arrow keys, which by
  // construction doesn't match a Ctrl-held press, so it shouldn't
  // independently consume this either — flagged as worth confirming on a
  // real device rather than asserted with full certainty, same caution
  // this codebase's own search_filter_panel.dart comment already takes
  // around this exact Slider's internal keyboard quirks.
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

    // Always active regardless of input mode or sub-menu state — this is
    // what actually closes a sub-menu, so it can't be gated behind "no
    // sub-menu open" the way the desktop-only bindings below are.
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
      case LogicalKeyboardKey.arrowRight when _isCtrlPressed:
        _exactSkipForward();
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
      // Escape while the batch picker is showing routes to the same
      // exit used by the picker's own close button — there's no partial
      // state to back out of otherwise.
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

  /// Fixed 90-second forward seek — see [_kExactSkipDuration]'s doc
  /// comment for why this is deliberately independent of chapter
  /// metadata. Shared by both entry points (Ctrl+→ in [_onKeyEvent], and
  /// the dedicated skip button in [TheaterControls]), so
  /// [_controlsVisibility]'s activity registration only needs to happen
  /// once, here, rather than being duplicated at each call site.
  void _exactSkipForward() {
    _controlsVisibility.registerActivity();
    final target = _player.state.position + _kExactSkipDuration;
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

  // Interaction brackets (seekbar/volume drag).
  //
  // A seekbar or volume-slider drag needs to suspend two independent
  // controllers at once — ControlsVisibilityController (so the bar
  // doesn't auto-hide mid-drag) and PlaybackStallController (so the
  // buffering blip a seek itself triggers never reads as a stall). These
  // two thin wrappers are what TheaterControls' onInteractionStart/
  // onInteractionEnd actually call, so both controllers stay in lockstep
  // without either one needing to know the other exists.
  void _handleInteractionStart() {
    _controlsVisibility.beginInteraction();
    _playbackStallController.beginInteraction();
  }

  void _handleInteractionEnd() {
    _controlsVisibility.endInteraction();
    _playbackStallController.endInteraction();
  }

  // Background gesture.

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

  // Window / exit.

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
    // Removed before any `await` below so a stray notifyListeners() firing
    // during this teardown sequence (a trailing FFI callback, a last
    // remote-poll tick) can never re-enter _onTorrentStateChanged and
    // reopen/replay against a Player that's about to be stopped and
    // disposed.
    _torrentController.removeListener(_onTorrentStateChanged);

    if (Platform.isAndroid || Platform.isIOS) {
      // Awaited here, matching _toggleFullscreen's pattern for the
      // identical pair of calls — this method is already async, so
      // there's no reason to leave these unawaited.
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
    _playbackDiagnostics.dispose();
    _autoSkipController.dispose();
    _playbackStallController.dispose();
    _topNotificationTimer?.cancel();
    await _posSub?.cancel();
    // Fires an armed-but-not-yet-committed AniList sync immediately
    // instead of letting _tracker.dispose() below silently cancel it —
    // see flushPendingCommit's doc comment.
    await _tracker.flushPendingCommit();
    _tracker.dispose();
    await _disposePlaybackResources();
    if (mounted) Navigator.pop(context);
  }

  /// Shared teardown for both restart paths this screen supports — the
  /// freeze-recovery restart button ([_handleRestartRequested]) and the
  /// Libass toggle ([_handleLibassToggle]) — up to (but not including)
  /// the final `Navigator.pop` with a [TheaterRestartRequest]. Each
  /// caller computes its own resume position and finishes any prep of
  /// its own (persisting the new setting, in the Libass case) before
  /// calling this, since both still need the *old* `_player` alive right
  /// up until this runs.
  ///
  /// Sets `_isClosing` and removes the torrent-controller listener as
  /// its first steps, for the same reason `_exitTheater` does — a stray
  /// `notifyListeners()` mid-teardown must never be able to reopen or
  /// replay against a `Player` that's on its way out.
  Future<void> _teardownForRestart() async {
    _isClosing = true;
    _torrentController.removeListener(_onTorrentStateChanged);

    _autoSkipController.dispose();
    _playbackDiagnostics.dispose();
    _playbackStallController.dispose();
    _topNotificationTimer?.cancel();
    await _posSub?.cancel();
    // The replacement TheaterScreen constructs a brand-new
    // AnilistTrackerService that re-fetches status from scratch — an
    // armed commit on this instance has to fire now or it's gone for
    // good, not just delayed to a "next tick" the way it would be if
    // this were an ordinary mid-playback timer.
    await _tracker.flushPendingCommit();
    _tracker.dispose();

    await _player.stop();
    await _player.dispose();
  }

  /// Handles a tap on TheaterTopBar's freeze-recovery button (only shown
  /// when `showFreezeRecoveryButton` is on). Disposing `_player` (inside
  /// [_teardownForRestart]) is what actually frees the stuck native
  /// texture behind the confirmed Linux/NVIDIA/Wayland freeze (see
  /// ARCHITECTURE.md § 7). Pops with a [TheaterRestartRequest] carrying
  /// the still-live, still-buffered `_torrentController` and a resume
  /// position a few seconds before wherever playback was.
  /// `_torrentController` is deliberately NOT disposed here:
  /// `StreamingController.dispose()` deletes downloaded torrent pieces
  /// and `RemoteStreamingController.dispose()` tears down the remote
  /// session, either of which would force a real re-download instead of
  /// a near-instant recovery. The caller (`runTheaterSession`) is
  /// expected to immediately re-push a fresh TheaterScreen using both
  /// values.
  Future<void> _handleRestartRequested() async {
    if (_isClosing) return;

    final rawResumePosition = _player.state.position - _kFreezeRecoveryRewind;
    final resumePosition = rawResumePosition.isNegative
        ? Duration.zero
        : rawResumePosition;

    await _teardownForRestart();

    if (mounted) {
      Navigator.pop(
        context,
        TheaterRestartRequest(
          resumeController: _torrentController,
          resumePosition: resumePosition,
        ),
      );
    }
  }

  /// Handles a toggle in [TheaterSettingsMenu]'s Libass row.
  /// `media_kit`'s `PlayerConfiguration.libass` is only ever read at
  /// `Player`-construction time — there's no exposed way to flip it on
  /// an already-running instance — so persisting the new value and then
  /// restarting via the same [TheaterRestartRequest] mechanism
  /// [_handleRestartRequested] uses is the only way to make the change
  /// take effect this session. Unlike freeze recovery, this always
  /// resumes at the *exact* position playback was at — nothing is
  /// actually wrong with the player here, so there's no reason to
  /// rewind.
  Future<void> _handleLibassToggle(bool newValue) async {
    if (_isClosing) return;

    final settingsController = SettingsScope.of(context, listen: false);
    final current = settingsController.settings;

    // Persisted (and SettingsController's own `_settings` updated)
    // before any teardown, so the fresh TheaterScreen `runTheaterSession`
    // immediately re-pushes reads the new value the instant its own
    // initState constructs a new Player — see this file's initState for
    // that read.
    await settingsController.update(
      AppSettings(
        filterEcchi: current.filterEcchi,
        hardwareDecoding: current.hardwareDecoding,
        androidHwDec: current.androidHwDec,
        autoPlayEnabled: current.autoPlayEnabled,
        autoSkip: current.autoSkip,
        showFreezeRecoveryButton: current.showFreezeRecoveryButton,
        uiPerformanceMode: current.uiPerformanceMode,
        videoFilterQuality: current.videoFilterQuality,
        serverMode: current.serverMode,
        serverUrl: current.serverUrl,
        libassEnabled: newValue,
      ),
    );

    if (!mounted || _isClosing) return;

    // No rewind, unlike _handleRestartRequested — see this method's doc
    // comment.
    final resumePosition = _player.state.position;
    await _teardownForRestart();

    if (mounted) {
      Navigator.pop(
        context,
        TheaterRestartRequest(
          resumeController: _torrentController,
          resumePosition: resumePosition,
        ),
      );
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);

    if (Platform.isAndroid || Platform.isIOS) {
      // dispose() must stay synchronous (it can't become async — the
      // required super.dispose() call has to happen in this same
      // synchronous frame), so these fire-and-forget calls are wrapped
      // explicitly instead of silently dropped (unawaited_futures).
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
    _playbackDiagnostics.dispose();
    _autoSkipController.dispose();
    _playbackStallController.dispose();
    _topNotificationTimer?.cancel();
    final posSub = _posSub;
    if (posSub != null) {
      unawaited(posSub.cancel());
    }
    _torrentController.removeListener(_onTorrentStateChanged);
    // Fire-and-forget, matching this method's existing pattern for
    // unavoidably-async cleanup — dispose() can't await. Idempotent if
    // _exitTheater/_teardownForRestart already flushed: their own call
    // already cancelled _delayTimer, so this one just no-ops. Only
    // meaningfully fires if this State is torn down through some path
    // that bypasses both of those (e.g. an ancestor route popping this
    // screen directly), which would otherwise drop an armed commit with
    // no flush at all.
    unawaited(_tracker.flushPendingCommit());
    _tracker.dispose();

    if (!_isClosing) {
      _isClosing = true;
      unawaited(Future.microtask(_disposePlaybackResources));
    }
    super.dispose();
  }

  // Video quality.

  FilterQuality _getFilterQuality() => switch (_videoFilterQuality) {
    'high' => FilterQuality.high,
    'medium' => FilterQuality.medium,
    'none' => FilterQuality.none,
    _ => FilterQuality.low,
  };

  // Controls overlay (top bar + control bar).
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
        // ExcludeFocus alongside IgnorePointer: the opacity/IgnorePointer
        // pair alone only blocks pointer hit-testing when controls are
        // hidden — keyboard/D-Pad focus could still land on (and stay
        // on) a fully invisible button. ExcludeFocus removes the whole
        // subtree from the focus tree entirely while excluding is true,
        // so hidden controls are genuinely unreachable, not just
        // untappable. Flutter moves focus elsewhere automatically if
        // something inside was focused right as this flips — the global
        // keyboard handler in _onKeyEvent doesn't depend on where focus
        // ends up after that, since it reads every key event directly
        // rather than via focus-chain bubbling.
        child: ExcludeFocus(
          excluding: !showControls,
          child: RepaintBoundary(
            child: Stack(
              children: [
                Positioned(
                  top: 24 + MediaQuery.paddingOf(context).top,
                  left: 24,
                  right: 24,
                  // DpadRegion: its own visual section, separate from
                  // the controls bar below. No edge-behavior overrides —
                  // default leave/leave lets Down escape into the
                  // controls region, and Up has nothing above it to
                  // find anyway. No tap-swallowing wrapper needed here:
                  // TheaterTopBar's own row paints nothing behind its
                  // children, so empty space around them already falls
                  // through to the root's background-tap handler.
                  child: DpadRegion(
                    memoryKey: 'theater.topbar',
                    child: TheaterTopBar(
                      title: _displayLabel,
                      uiPerformanceMode: _uiPerformanceMode,
                      showFreezeRecoveryButton: _showFreezeRecoveryButton,
                      onBack: _exitTheater,
                      onRestart: _handleRestartRequested,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  // No tap-swallowing wrapper here either. TheaterControls'
                  // gradient Container paints across nearly its entire
                  // bounds, but under Flutter's standard nested-
                  // GestureDetector resolution a descendant's own tap
                  // recognizer (an actual button) still wins the gesture
                  // arena over an ancestor's — so real buttons keep
                  // working, while a tap on empty gradient space falls
                  // through to the root GestureDetector's onTap
                  // (_handleBackgroundTap) in build() below.
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
                      onInteractionStart: _handleInteractionStart,
                      onInteractionEnd: _handleInteractionEnd,
                      onToggleSettings: () =>
                          setState(() => _isSettingsOpen = !_isSettingsOpen),
                      onExactSkip: _exactSkipForward,
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

  // Build.

  @override
  Widget build(BuildContext context) {
    final dpadModeActive = InputModeScope.of(context).dpadModeActive;

    // The video texture, the top notification, the settings-menu popup,
    // and the loading/batch-picker overlay switcher don't depend on
    // controls visibility at all — they're computed once per real
    // setState() (video-ready, settings toggle, chapters loaded, a new
    // notification arriving, etc.). Passed as the `child` of the
    // ValueListenableBuilder below so this subtree is reused, not
    // rebuilt, on every controls-visibility transition.
    final staticLayer = Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _videoInitialized ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          // RepaintBoundary: the video texture updates on every decoded
          // frame (dozens of times/sec) completely independently of the
          // controls overlay above it (which only repaints on user
          // interaction/position ticks). Without a boundary here, Flutter
          // has no reason to treat them as separate compositor layers,
          // so a control-bar repaint could force the video's layer to be
          // re-recorded too, and vice versa. This pins the video to its
          // own stable, GPU-cacheable layer.
          child: RepaintBoundary(
            child: Video(
              controller: _videoController,
              // NoVideoControls is media_kit_video's `const dynamic`
              // sentinel for "no controls builder" — its actual runtime
              // value is `null`, not a function. The parameter itself is
              // nullable (VideoControlsBuilder?), so the cast target
              // must be nullable too, or casting null throws at runtime
              // (confirmed via crash log: "type 'Null' is not a subtype
              // of type '(VideoState) => Widget' in type cast").
              controls: NoVideoControls as Widget Function(VideoState)?,
              filterQuality: _getFilterQuality(),
            ),
          ),
        ),

        // Gated on _videoInitialized rather than shown unconditionally —
        // PlaybackStallController starts observing mpv in initState, well
        // before Player.open()/.play() are ever called, so without this
        // gate a slow initial buffer-up could theoretically race the
        // fade from TheaterLoadingOverlay into the video and show both
        // at once. Independent of controls-bar visibility on purpose: a
        // stall needs to stay visible even while the user is watching
        // hands-off with the control bar auto-hidden, so this reads
        // directly off PlaybackStallController.visible via its own small
        // ValueListenableBuilder rather than living inside
        // _buildControlsOverlay's opacity-gated subtree.
        if (_videoInitialized)
          ValueListenableBuilder<bool>(
            valueListenable: _playbackStallController.visible,
            builder: (context, stalled, _) => PlaybackStallIndicator(
              visible: stalled,
              uiPerformanceMode: _uiPerformanceMode,
            ),
          ),

        // Rendered regardless of controls-overlay visibility, so a
        // sync/skip status message stays reachable even while the
        // controls bar has auto-hidden. Positioned _kTopBarClearance
        // below TheaterTopBar's own top offset above, so the two can
        // never occupy the same space.
        Positioned(
          top: 24 + MediaQuery.paddingOf(context).top + _kTopBarClearance,
          left: 16,
          right: 16,
          child: TheaterTopNotification(
            message: _topNotification?.message,
            icon: _topNotification?.icon,
            iconColor: _topNotification?.iconColor,
            uiPerformanceMode: _uiPerformanceMode,
          ),
        ),

        if (_isSettingsOpen)
          Positioned(
            bottom: 110,
            right: 32,
            child: TheaterSettingsMenu(
              player: _player,
              uiPerformanceMode: _uiPerformanceMode,
              libassEnabled: _libassEnabled,
              onToggleLibass: (newValue) =>
                  unawaited(_handleLibassToggle(newValue)),
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
                  // Exits Theater entirely, matching what Escape does in
                  // the same state (see _handleBackOrEscape) — there's
                  // no partial "fullscreen exit" to do here since no
                  // stream has started yet.
                  onBack: _exitTheater,
                );
              }
              return TheaterLoadingOverlay(
                title: _displayLabel,
                controller: _torrentController,
              );
            },
          ),
        ),
      ],
    );

    return PopScope(
      // Never lets a bare pop through directly — both branches below
      // always explicitly handle it (exit fullscreen and stay, or run
      // _exitTheater's careful async teardown sequence before popping).
      // This is what maybePop() — called from _handleBackOrEscape above,
      // and from Dpad.wrap()'s root-level onBack via the same
      // Navigator.maybePop() path — resolves to. One mechanism,
      // reachable from the system back gesture, a desktop Escape key,
      // and the D-Pad remote's dedicated Back key alike. A direct
      // Navigator.pop() call (as _exitTheater's own last line and
      // _teardownForRestart's callers both do) bypasses this guard
      // entirely — canPop only intercepts involuntary pop attempts, not
      // explicit ones from this screen's own code.
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
          // ValueListenableBuilder scoped to controls visibility only —
          // MouseRegion's cursor and the controls overlay's opacity/
          // hit-testing both depend on it, but `staticLayer` above
          // (video, top notification, settings menu, loading/batch-picker
          // overlay) does not, and is passed as `child` so it's reused
          // rather than reconstructed on every show/hide transition.
          // registerActivity() writes to a ValueNotifier, which only
          // notifies listeners on a genuine true→false/false→true
          // transition — so hovering with controls already visible
          // costs a cancelled+rescheduled Timer, not a rebuild of
          // anything visual.
          child: ValueListenableBuilder<bool>(
            valueListenable: _controlsVisibility.visible,
            child: staticLayer,
            builder: (context, showControls, child) {
              return MouseRegion(
                cursor: showControls
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.none,
                onHover: (_) => _controlsVisibility.registerActivity(),
                // opaque (not the default deferToChild): guarantees a
                // tap anywhere in this Stack — including areas where
                // nothing paints, like gaps around the IgnorePointer'd
                // controls overlay while it's hidden — reaches this
                // detector's own onTap. Real interactive descendants
                // (buttons, the settings menu's close button, etc.) are
                // unaffected: a descendant's own tap recognizer still
                // wins the gesture arena over this ancestor's, by
                // Flutter's standard nested-GestureDetector resolution —
                // opaque only changes whether empty space counts as a
                // hit, not how competing recognizers along the same
                // hit-test chain resolve against each other.
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
