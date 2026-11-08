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
import '../../data/torrent/models/torrent.dart';
import 'services/auto_skip_controller.dart';
import 'services/controls_visibility_controller.dart';
import 'services/mpv_chapter_loader.dart';
import 'services/next_episode_prefetch_controller.dart';
import 'services/playback_diagnostics.dart';
import 'services/playback_handle.dart';
import 'services/playback_stall_controller.dart';
import 'services/player_configurator.dart';
import 'services/streaming_controller.dart';
import 'services/streaming_controller_base.dart';
import 'services/theater_data.dart';
import 'services/top_notification_controller.dart';
import 'widgets/batch_picker.dart';
import 'widgets/mobile_theater_controls.dart';
import 'widgets/playback_stall_indicator.dart';
import 'widgets/theater_controls.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_settings.dart';

/// Non-null pop values of [TheaterScreen]; a `null` pop is a genuine exit.
/// See ARCHITECTURE.md § 9.
sealed class TheaterExitResult {
  const TheaterExitResult();
}

/// Pop result for a freeze-recovery restart or a Libass toggle; carries the
/// still-buffered session to the replacement [TheaterScreen].
class TheaterRestartRequest extends TheaterExitResult {
  final BaseStreamingController resumeController;
  final Duration resumePosition;

  const TheaterRestartRequest({
    required this.resumeController,
    required this.resumePosition,
  });
}

/// How [AnimeDetailsScreen._streamTorrent] proceeds after a
/// [TheaterNextEpisodeRequest].
enum NextEpisodeTransitionMode {
  /// A prefetched, buffering controller is ready; re-push [TheaterScreen]
  /// against it directly.
  instantHandoff,

  /// No prewarmed controller, autoplay on: fetch and stream the next
  /// episode's top-scored torrent.
  autoFetch,

  /// Autoplay off: open the torrent-selection modal for the next episode.
  manualPick,
}

/// Pop result for end-of-episode or the Next Episode chip. The prewarmed
/// fields are set only for [NextEpisodeTransitionMode.instantHandoff].
class TheaterNextEpisodeRequest extends TheaterExitResult {
  final int nextEpisode;
  final NextEpisodeTransitionMode mode;
  final BaseStreamingController? prewarmedController;
  final Torrent? prewarmedTorrent;

  const TheaterNextEpisodeRequest({
    required this.nextEpisode,
    required this.mode,
    this.prewarmedController,
    this.prewarmedTorrent,
  }) : assert(
         mode != NextEpisodeTransitionMode.instantHandoff ||
             (prewarmedController != null && prewarmedTorrent != null),
         'instantHandoff requires both prewarmedController and prewarmedTorrent',
       );
}

class TheaterScreen extends StatefulWidget {
  /// AniList context for progress tracking; null together with [episode] and
  /// [totalEpisodes] for a custom magnet.
  final Anime? anime;

  /// Paired with [anime]; also the batch-file auto-match hint.
  final int? episode;

  /// The magnet link to stream.
  final String magnetUri;

  /// Top-bar/loading label in place of "Episode N" when [episode] is null.
  final String? displayTitle;

  /// Episode count for [anime]; gates the Next Episode chip and completion
  /// transitions.
  final int? totalEpisodes;

  /// A still-buffered controller to resume from after a restart.
  final BaseStreamingController? resumeController;

  /// Where to seek once the resumed stream reopens; paired with
  /// [resumeController].
  final Duration? resumePosition;

  const TheaterScreen({
    super.key,
    this.anime,
    this.episode,
    required this.magnetUri,
    this.displayTitle,
    this.totalEpisodes,
    this.resumeController,
    this.resumePosition,
  }) : assert(
         (resumeController == null) == (resumePosition == null),
         'resumeController and resumePosition must both be null or both be provided',
       ),
       assert(
         (anime == null) == (episode == null) &&
             (episode == null) == (totalEpisodes == null),
         'anime, episode, and totalEpisodes must all be null (a custom '
         'magnet stream with no episode context) or all be provided',
       );

  @override
  State<TheaterScreen> createState() => _TheaterScreenState();
}

class _TheaterScreenState extends State<TheaterScreen> {
  BaseStreamingController _torrentController = StreamingController();

  late final AnilistTrackerService _tracker;
  late final Player _player;
  late final PlaybackHandle _playbackHandle;
  late final VideoController _videoController;
  late final AutoSkipController _autoSkipController;
  late final ControlsVisibilityController _controlsVisibility;

  late final PlaybackDiagnostics _playbackDiagnostics;
  late final PlaybackStallController _playbackStallController;

  // Null with no next episode or no episode context; built in
  // _initPlayerAndStream.
  NextEpisodePrefetchController? _prefetchController;

  /// How far before the current position a freeze-recovery restart resumes.
  static const Duration _kFreezeRecoveryRewind = Duration(seconds: 5);

  /// Fixed 90 s forward seek (Ctrl+→ or the skip button), ignoring chapters.
  static const Duration _kExactSkipDuration = Duration(minutes: 1, seconds: 30);

  bool _videoInitialized = false;
  bool _isSettingsOpen = false;
  bool _isFullscreen = true;
  bool _isClosing = false;

  // Written by the controls' focus callbacks and read only by _onKeyEvent, so
  // no setState.
  bool _seekbarFocused = false;
  bool _volumeSliderFocused = false;

  bool _autoSkip = false;

  // Picks the mode in _requestNextEpisodeTransition; separate from
  // auto-torrent-selection, which this screen never reads.
  bool _episodeAutoplayEnabled = false;

  bool _showFreezeRecoveryButton = false;

  // Performance settings.
  bool _uiPerformanceMode = false;
  String _videoFilterQuality = 'low';

  /// The libass setting [_player] is built with; seeds the settings toggle.
  late bool _libassEnabled;

  List<Chapter> _chapters = [];
  StreamSubscription<Duration>? _posSub;

  // Subscribed in initState: completion doesn't depend on
  // _initPlayerAndStream's async setup.
  StreamSubscription<bool>? _completedSub;

  final TopNotificationController _topNotificationController =
      TopNotificationController();

  /// "Episode N", else [TheaterScreen.displayTitle] or "Custom Stream".
  String get _displayLabel => widget.episode != null
      ? 'Episode ${widget.episode}'
      : (widget.displayTitle ?? 'Custom Stream');

  @override
  void initState() {
    super.initState();

    _libassEnabled = SettingsScope.of(
      context,
      listen: false,
    ).settings.libassEnabled;

    // See ARCHITECTURE.md § 5.
    _player = Player(
      configuration: PlayerConfiguration(libass: _libassEnabled),
    );
    // Consumed by MobileTheaterControls on non-desktop platforms.
    _playbackHandle = PlayerPlaybackHandle(_player);
    const videoConfig = VideoControllerConfiguration(
      androidAttachSurfaceAfterVideoParameters: true,
    );
    _videoController = VideoController(_player, configuration: videoConfig);

    _controlsVisibility = ControlsVisibilityController(
      playingStream: _player.stream.playing,
      isPlaying: () => _player.state.playing,
      isSubMenuOpen: () => _isSettingsOpen,
    );
    _playbackDiagnostics = PlaybackDiagnostics(player: _player);
    _playbackStallController = PlaybackStallController(player: _player);
    _completedSub = _player.stream.completed.listen(_onPlaybackCompleted);

    if (Platform.isAndroid || Platform.isIOS) {
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
      onSeek: (position) => _player.seek(position),
      isEnabled: () => _autoSkip,
      onSkipArmed: (skipLabel) {
        if (mounted) {
          _topNotificationController.show(
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
          _topNotificationController.show(
            message: 'Progress saved to AniList',
            icon: Icons.check_circle_rounded,
            iconColor: AppPalette.statusReleasing,
          );
        }
      },
      onFailure: (message) {
        if (mounted) {
          _topNotificationController.show(
            message: message,
            icon: Icons.error_outline_rounded,
            iconColor: AppPalette.statusCancelled,
          );
        }
      },
    );

    unawaited(_initPlayerAndStream());
    _controlsVisibility.registerActivity();

    // Registered last, once every field the handler reads is initialized.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  Future<void> _initPlayerAndStream() async {
    if (!mounted) return;

    final s = SettingsScope.of(context, listen: false).settings;

    setState(() {
      _uiPerformanceMode = s.uiPerformanceMode;
      _videoFilterQuality = s.videoFilterQuality;
      _autoSkip = s.autoSkip;
      _episodeAutoplayEnabled = s.episodeAutoplayEnabled;
      _showFreezeRecoveryButton = s.showFreezeRecoveryButton;
    });

    final bool isResuming = widget.resumeController != null;

    final BaseStreamingController newController =
        widget.resumeController ?? createStreamingController(s);
    newController.addListener(_onTorrentStateChanged);

    if (!mounted) {
      // Dispose only a controller built here; a resumed one belongs to the
      // prior screen.
      if (!isResuming) newController.dispose();
      return;
    }

    final oldPlaceholder = _torrentController;
    setState(() => _torrentController = newController);

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => oldPlaceholder.dispose(),
    );

    await PlayerConfigurator.configureForTheater(_player, s);

    // Fullscreen is forced only on desktop with hwdec on "auto".
    if (s.hardwareDecoding == 'auto' &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      await windowManager.setFullScreen(true);
    }

    // Restores persistent volume.
    final savedVolume =
        await SharedPreferencesAsync().getDouble('theater_volume') ?? 100.0;
    await _player.setVolume(savedVolume);

    if (isResuming) {
      // Readiness already fired on the replaced screen, so check it directly.
      _onTorrentStateChanged();
    } else {
      // Not awaited: readiness arrives via notifyListeners, and awaiting would
      // delay tracker init.
      unawaited(
        _torrentController.initialize(
          widget.magnetUri,
          episodeNumber: widget.episode,
        ),
      );
    }

    // Skipped for custom-magnet sessions (no episode context); an un-init'd
    // tracker's updateProgress() is a no-op.
    final trackedAnime = widget.anime;
    final trackedEpisode = widget.episode;
    final trackedTotalEpisodes = widget.totalEpisodes;
    if (trackedAnime != null && trackedEpisode != null) {
      await _tracker.init(
        mediaId: trackedAnime.id,
        episode: trackedEpisode,
        totalEpisodes: trackedAnime.episodes,
      );
    }
    if (!mounted) return;

    if (trackedAnime != null &&
        trackedEpisode != null &&
        trackedTotalEpisodes != null &&
        trackedEpisode < trackedTotalEpisodes) {
      _prefetchController = NextEpisodePrefetchController(
        anime: trackedAnime,
        nextEpisode: trackedEpisode + 1,
        settings: s,
        episodeAutoplayEnabled: () => _episodeAutoplayEnabled,
        onEngineWarm: () {
          if (mounted) {
            _topNotificationController.show(
              message: 'Up next: Episode ${trackedEpisode + 1} ready',
              icon: Icons.skip_next_rounded,
              iconColor: AppPalette.primary,
            );
          }
        },
      );
    }

    _posSub = _player.stream.position.listen((pos) {
      _tracker.updateProgress(pos, _player.state.duration);
      _autoSkipController.onPosition(pos);
      _prefetchController?.onPosition(pos, _player.state.duration);
    });
  }

  // Controller listener.

  void _onTorrentStateChanged() {
    // See ARCHITECTURE.md § 9.
    if (_isClosing) return;
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      setState(() => _videoInitialized = true);
      unawaited(_player.open(Media(_torrentController.streamUrl!)));

      final resumePosition = widget.resumePosition;
      if (resumePosition != null) {
        // open() resolves before the file loads, so seek only once duration is
        // known; play() waits for the seek so a restart never flashes frame 0.
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

  // Platform: picks the bottom control bar and gates desktop-only controls.
  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// True while either Ctrl key is held; backs the Ctrl+→ exact skip.
  bool get _isCtrlPressed =>
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.controlLeft,
      ) ||
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.controlRight,
      );

  // Keyboard shortcuts (desktop). See DESIGN.md § 4.
  bool _onKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;

    // Esc/Back always fire: this is what closes a sub-menu.
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _handleBackOrEscape();
      return true;
    }

    final isTvPlatform = InputModeScope.of(context, listen: false).isTvPlatform;
    final subMenuOpen =
        _isSettingsOpen || _torrentController.needsManualSelection;
    if (isTvPlatform || subMenuOpen) return false;

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
      // Same exit as the batch picker's close button.
      unawaited(_exitTheater());
      return;
    }
    // maybePop() runs the PopScope below, where the fullscreen-then-exit
    // decision lives.
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

  /// Shared by Ctrl+→ and the skip button; see [_kExactSkipDuration].
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

  // Interaction brackets (seekbar/volume drag): suspend auto-hide and stall
  // detection together, so a seek's own buffering blip never reads as a stall.
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
    _playbackHandle.dispose();
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
    _torrentController.removeListener(_onTorrentStateChanged);

    if (Platform.isAndroid || Platform.isIOS) {
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
    _prefetchController?.dispose();
    _playbackDiagnostics.dispose();
    _autoSkipController.dispose();
    _playbackStallController.dispose();
    _topNotificationController.cancelPendingHide();
    await _posSub?.cancel();
    await _completedSub?.cancel();
    // See ARCHITECTURE.md § 9.
    await _tracker.flushPendingCommit();
    _tracker.dispose();
    await _disposePlaybackResources();
    if (mounted) Navigator.pop(context);
  }

  /// Teardown for both restart paths, up to the final pop; callers read the
  /// resume position first, while [_player] is still alive.
  Future<void> _teardownForRestart() async {
    _isClosing = true;
    _torrentController.removeListener(_onTorrentStateChanged);

    _prefetchController?.dispose();
    _autoSkipController.dispose();
    _playbackDiagnostics.dispose();
    _playbackStallController.dispose();
    _topNotificationController.cancelPendingHide();
    await _posSub?.cancel();
    await _completedSub?.cancel();
    await _tracker.flushPendingCommit();
    _tracker.dispose();

    await _player.stop();
    await _player.dispose();
    _playbackHandle.dispose();
  }

  /// Freeze-recovery restart: pops with a [TheaterRestartRequest] resuming
  /// [_kFreezeRecoveryRewind] earlier (ARCHITECTURE.md § 7). Hands off
  /// [_torrentController] undisposed, since its dispose() deletes pieces or
  /// tears down the remote session.
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

  /// Persists the new Libass value, then restarts at the exact position; no
  /// rewind, since nothing is wrong with the player.
  Future<void> _handleLibassToggle(bool newValue) async {
    if (_isClosing) return;

    final settingsController = SettingsScope.of(context, listen: false);
    final current = settingsController.settings;

    // Persisted first so the replacement's initState reads the new value.
    await settingsController.update(
      AppSettings(
        filterEcchi: current.filterEcchi,
        hardwareDecoding: current.hardwareDecoding,
        androidHwDec: current.androidHwDec,
        autoTorrentEnabled: current.autoTorrentEnabled,
        episodeAutoplayEnabled: current.episodeAutoplayEnabled,
        autoSkip: current.autoSkip,
        showFreezeRecoveryButton: current.showFreezeRecoveryButton,
        uiPerformanceMode: current.uiPerformanceMode,
        videoFilterQuality: current.videoFilterQuality,
        useExoPlayer: current.useExoPlayer,
        serverMode: current.serverMode,
        serverUrl: current.serverUrl,
        libassEnabled: newValue,
      ),
    );

    if (!mounted || _isClosing) return;

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

  // Episode transition (next-episode autoplay / manual "Next Episode").

  /// End-of-file listener; routes into [_requestNextEpisodeTransition].
  void _onPlaybackCompleted(bool completed) {
    if (!completed) return;
    unawaited(_requestNextEpisodeTransition());
  }

  /// Shared by the Next Episode chip and playback completion; no-ops without a
  /// next episode or once closing, which absorbs a same-frame double fire.
  Future<void> _requestNextEpisodeTransition() async {
    if (_isClosing) return;

    final episode = widget.episode;
    final totalEpisodes = widget.totalEpisodes;
    if (episode == null || totalEpisodes == null) return;

    final nextEpisode = episode + 1;
    if (nextEpisode > totalEpisodes) return;

    final NextEpisodeTransitionMode mode;
    BaseStreamingController? prewarmedController;
    Torrent? prewarmedTorrent;

    if (_episodeAutoplayEnabled) {
      // takeWarmResult() transfers ownership of the warm controller to the
      // request; with nothing warm this falls through to a fresh fetch.
      final warm = _prefetchController?.takeWarmResult();
      if (warm != null) {
        mode = NextEpisodeTransitionMode.instantHandoff;
        prewarmedController = warm.controller;
        prewarmedTorrent = warm.torrent;
      } else {
        mode = NextEpisodeTransitionMode.autoFetch;
      }
    } else {
      mode = NextEpisodeTransitionMode.manualPick;
    }

    await _teardownForNextEpisode();

    if (mounted) {
      Navigator.pop(
        context,
        TheaterNextEpisodeRequest(
          nextEpisode: nextEpisode,
          mode: mode,
          prewarmedController: prewarmedController,
          prewarmedTorrent: prewarmedTorrent,
        ),
      );
    }
  }

  /// Teardown for an episode transition; unlike a restart, [_torrentController]
  /// is disposed, not handed off.
  Future<void> _teardownForNextEpisode() async {
    _isClosing = true;
    _torrentController.removeListener(_onTorrentStateChanged);

    _prefetchController?.dispose();
    _autoSkipController.dispose();
    _playbackDiagnostics.dispose();
    _playbackStallController.dispose();
    _topNotificationController.cancelPendingHide();
    await _posSub?.cancel();
    await _completedSub?.cancel();
    await _tracker.flushPendingCommit();
    _tracker.dispose();

    await _player.stop();
    await _player.dispose();
    _torrentController.dispose();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);

    if (Platform.isAndroid || Platform.isIOS) {
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
    _prefetchController?.dispose();
    _playbackDiagnostics.dispose();
    _autoSkipController.dispose();
    _playbackStallController.dispose();
    _topNotificationController.dispose();
    final posSub = _posSub;
    if (posSub != null) {
      unawaited(posSub.cancel());
    }
    final completedSub = _completedSub;
    if (completedSub != null) {
      unawaited(completedSub.cancel());
    }
    _torrentController.removeListener(_onTorrentStateChanged);
    // Idempotent after a teardown's flush; only fires when an ancestor route
    // pops this screen directly.
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

  // Controls overlay (top bar + control bar), parameterized because build()'s
  // ValueListenableBuilder calls it. Desktop gets TheaterControls; Android and
  // iOS (TV included) get MobileTheaterControls, which has no D-pad wiring.
  Widget _buildControlsOverlay(bool showControls, bool isTvPlatform) {
    final hasNextEpisode =
        widget.episode != null &&
        widget.totalEpisodes != null &&
        widget.episode! < widget.totalEpisodes!;

    final bottomBar = _isDesktopPlatform
        ? DpadRegion(
            memoryKey: 'theater.controls',
            child: TheaterControls(
              player: _player,
              chapterMetadata: _chapters,
              isSettingsOpen: _isSettingsOpen,
              isFullscreen: _isFullscreen,
              isDesktop: _isDesktopPlatform,
              uiPerformanceMode: _uiPerformanceMode,
              isTvPlatform: isTvPlatform,
              onToggleFullscreen: _toggleFullscreen,
              onInteract: _controlsVisibility.registerActivity,
              onInteractionStart: _handleInteractionStart,
              onInteractionEnd: _handleInteractionEnd,
              onToggleSettings: () =>
                  setState(() => _isSettingsOpen = !_isSettingsOpen),
              onExactSkip: _exactSkipForward,
              onSeekbarFocusChange: (f) => _seekbarFocused = f,
              onVolumeFocusChange: (f) => _volumeSliderFocused = f,
              hasNextEpisode: hasNextEpisode,
              onNextEpisode: () => unawaited(_requestNextEpisodeTransition()),
            ),
          )
        : MobileTheaterControls(
            playback: _playbackHandle,
            chapterMetadata: _chapters,
            isSettingsOpen: _isSettingsOpen,
            uiPerformanceMode: _uiPerformanceMode,
            onInteract: _controlsVisibility.registerActivity,
            onInteractionStart: _handleInteractionStart,
            onInteractionEnd: _handleInteractionEnd,
            onToggleSettings: () =>
                setState(() => _isSettingsOpen = !_isSettingsOpen),
            onSeekbarFocusChange: (f) => _seekbarFocused = f,
          );

    return AnimatedOpacity(
      opacity: showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !showControls,
        // ExcludeFocus too: IgnorePointer alone leaves hidden buttons
        // reachable by keyboard/D-pad.
        child: ExcludeFocus(
          excluding: !showControls,
          child: RepaintBoundary(
            child: Stack(
              children: [
                Positioned(
                  top: 24 + MediaQuery.paddingOf(context).top,
                  left: 24,
                  right: 24,
                  // Own region; Down escapes into the controls.
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
                  // No tap-swallowing wrapper: a button's recognizer wins the
                  // gesture arena, and taps on empty gradient fall through to
                  // _handleBackgroundTap.
                  child: bottomBar,
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
    final isTvPlatform = InputModeScope.of(context).isTvPlatform;

    // Independent of controls visibility; passed as the builder's child below.
    final staticLayer = Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _videoInitialized ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          // Own layer: the video repaints per frame, apart from the controls.
          child: RepaintBoundary(
            child: Video(
              controller: _videoController,
              // NoVideoControls is a `const dynamic` that is null at runtime,
              // so the cast target must be nullable.
              controls: NoVideoControls as Widget Function(VideoState)?,
              filterQuality: _getFilterQuality(),
            ),
          ),
        ),

        // Gated on _videoInitialized so a slow first buffer can't show this and
        // the loading overlay together. Reads the notifier directly so a stall
        // stays visible while the controls are hidden.
        if (_videoInitialized)
          ValueListenableBuilder<bool>(
            valueListenable: _playbackStallController.visible,
            builder: (context, stalled, _) => PlaybackStallIndicator(
              visible: stalled,
              uiPerformanceMode: _uiPerformanceMode,
            ),
          ),

        // Independent of controls visibility; shows with the bar hidden.
        Positioned(
          top:
              24 +
              MediaQuery.paddingOf(context).top +
              TheaterTopNotification.kTopBarClearance,
          left: 16,
          right: 16,
          child: ValueListenableBuilder<TopNotificationData?>(
            valueListenable: _topNotificationController.notification,
            builder: (context, data, _) => TheaterTopNotification(
              message: data?.message,
              icon: data?.icon,
              iconColor: data?.iconColor,
              uiPerformanceMode: _uiPerformanceMode,
            ),
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
                  // Same exit as Escape in this state (_handleBackOrEscape).
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
      // See ARCHITECTURE.md § 9.
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
          // See ARCHITECTURE.md § 3.
          child: ValueListenableBuilder<bool>(
            valueListenable: _controlsVisibility.visible,
            child: staticLayer,
            builder: (context, showControls, child) {
              return MouseRegion(
                cursor: showControls
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.none,
                onHover: (_) => _controlsVisibility.registerActivity(),
                // opaque so taps on empty space (e.g. around the hidden
                // controls) reach onTap; descendants' own recognizers still
                // win the gesture arena.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleBackgroundTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child!,
                      if (_videoInitialized)
                        _buildControlsOverlay(showControls, isTvPlatform),
                      // After the controls overlay so it hit-tests above it;
                      // the bottom bar's BoxDecoration hits across its full
                      // rect and would swallow the popup's clicks.
                      if (_isSettingsOpen)
                        Positioned(
                          // Same bottom as ExoTheaterScreen; desktop insets
                          // further right.
                          bottom: 130,
                          right: _isDesktopPlatform ? 32 : 16,
                          child: DesktopTheaterSettingsMenu(
                            player: _player,
                            uiPerformanceMode: _uiPerformanceMode,
                            onClose: () =>
                                setState(() => _isSettingsOpen = false),
                            libassEnabled: _libassEnabled,
                            onToggleLibass: (v) =>
                                unawaited(_handleLibassToggle(v)),
                          ),
                        ),
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