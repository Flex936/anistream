import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/anilist_tracker_service.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/torrent/models/torrent.dart';
import '../../shared/utils/perf_animations.dart';
import 'services/auto_skip_controller.dart';
import 'services/controls_visibility_controller.dart';
import 'services/native_chapter_parser.dart';
import 'services/native_subtitle_parser.dart';
import 'services/playback_handle.dart';
import 'services/remote_streaming_controller.dart';
import 'services/streaming_controller.dart';
import 'services/streaming_controller_base.dart';
import 'services/theater_data.dart';
import 'services/top_notification_controller.dart';
import 'services/track_name_parser.dart';
import 'widgets/batch_picker.dart';
import 'widgets/mobile_theater_controls.dart';
import 'widgets/styled_subtitle_view.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_settings.dart';

const bool kUseHardwareOverlay = false;

const NativeSubtitleFormat kSubtitleFormat = NativeSubtitleFormat.ass;

class ExoTheaterScreen extends StatefulWidget {
  final Anime anime;
  final int episode;
  final Torrent torrent;

  const ExoTheaterScreen({
    super.key,
    required this.anime,
    required this.episode,
    required this.torrent,
  });

  @override
  State<ExoTheaterScreen> createState() => _ExoTheaterScreenState();
}

class _ExoTheaterScreenState extends State<ExoTheaterScreen> {
  BaseStreamingController _torrentController = StreamingController();
  VideoPlayerController? _videoController;
  PlaybackHandle? _playbackHandle;

  ControlsVisibilityController? _controlsVisibility;

  bool _videoInitialized = false;
  String? _playerError;

  bool _isSettingsOpen = false;
  bool _isClosing = false;
  bool _uiPerformanceMode = false;

  bool _seekbarFocused = false;

  late final AutoSkipController _autoSkipController;
  bool _autoSkip = false;
  List<Chapter> _chapters = [];
  StreamSubscription<Duration>? _posSub;

  late final AnilistTrackerService _tracker;

  final TopNotificationController _topNotificationController =
      TopNotificationController();

  int? _selectedSubtitleIndex;
  bool _subtitleFetchTriggered = false;
  bool _subtitleAutoApplied = false;
  List<StyledCue> _styledCues = [];
  Timer? _subtitleContentTimer;

  List<VideoAudioTrack> _audioTracks = [];
  String? _selectedAudioTrackId;

  @override
  void initState() {
    super.initState();
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

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    _autoSkipController = AutoSkipController(
      onSeek: (position) => _playbackHandle?.seek(position) ?? Future.value(),
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

    unawaited(_initStreamAndPlayer());
  }

  Future<void> _initStreamAndPlayer() async {
    if (!mounted) return;
    final s = SettingsScope.of(context, listen: false).settings;

    setState(() {
      _uiPerformanceMode = s.uiPerformanceMode;
      _autoSkip = s.autoSkip;
    });

    final BaseStreamingController newController =
        (s.serverMode && s.serverUrl.isNotEmpty)
        ? RemoteStreamingController(serverUrl: s.serverUrl)
        : StreamingController();
    newController.addListener(_onTorrentStateChanged);

    if (!mounted) {
      newController.dispose();
      return;
    }

    setState(() => _torrentController = newController);
    unawaited(
      _torrentController.initialize(
        widget.torrent.magnetLink,
        episodeNumber: widget.episode,
      ),
    );

    await _tracker.init(
      mediaId: widget.anime.id,
      episode: widget.episode,
      totalEpisodes: widget.anime.episodes,
    );
  }

  void _onTorrentStateChanged() {
    if (_torrentController.isReadyToPlay && _videoController == null) {
      unawaited(_openVideoPlayer(_torrentController.streamUrl!));
    }

    if (_torrentController.subtitlesAvailable &&
        _torrentController.subtitleTracks.isEmpty &&
        !_subtitleFetchTriggered) {
      _subtitleFetchTriggered = true;
      unawaited(_torrentController.fetchSubtitleTracks());
    }
    if (_torrentController.subtitleTracks.isNotEmpty && !_subtitleAutoApplied) {
      _subtitleAutoApplied = true;
      unawaited(
        _applySubtitleTrack(
          _torrentController.subtitleTracks.first.streamIndex,
        ),
      );
    }

    if (mounted) setState(() {});
  }

  Future<void> _openVideoPlayer(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _playerError = 'video_player failed: $e');
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    final handle = VideoPlayerPlaybackHandle(controller);

    final savedVolume =
        await SharedPreferencesAsync().getDouble('theater_volume') ?? 100.0;
    await handle.setVolume(savedVolume);

    await controller.play();

    if (!mounted) {
      handle.dispose();
      await controller.dispose();
      return;
    }

    final controlsVisibility = ControlsVisibilityController(
      playingStream: handle.playingStream,
      isPlaying: () => handle.isPlaying,
      isSubMenuOpen: () => _isSettingsOpen,
    );

    setState(() {
      _videoController = controller;
      _playbackHandle = handle;
      _controlsVisibility = controlsVisibility;
      _videoInitialized = true;
    });
    controlsVisibility.registerActivity();

    _posSub = handle.positionStream.listen((pos) {
      _tracker.updateProgress(pos, handle.duration);
      _autoSkipController.onPosition(pos);
    });

    unawaited(_fetchChapters(url, handle));
    unawaited(_fetchAudioTracks(handle));
  }

  Future<void> _fetchChapters(String url, PlaybackHandle handle) async {
    try {
      final raw = await NativeChapterParser.extractChapters(url);
      if (!mounted) return;

      final markers = raw
          .where((m) => !m.hidden)
          .map(
            (m) => RawChapterMarker(
              title: m.title ?? 'Chapter',
              start: Duration(milliseconds: m.startMs),
            ),
          )
          .toList();

      final chapters = buildChaptersFromRaw(markers, handle.duration);
      if (!mounted) return;

      setState(() => _chapters = chapters);
      _autoSkipController.chapters = chapters;
    } catch (e) {
      AppLogger.w('ExoTheaterScreen', 'Chapter probe failed: $e');
    }
  }

  Future<void> _fetchAudioTracks(PlaybackHandle handle) async {
    try {
      final tracks = await handle.getAudioTracks();
      if (!mounted) return;

      VideoAudioTrack? selected;
      for (final t in tracks) {
        if (t.isSelected) {
          selected = t;
          break;
        }
      }

      setState(() {
        _audioTracks = tracks;
        _selectedAudioTrackId = selected?.id;
      });
    } catch (e) {
      AppLogger.w('ExoTheaterScreen', 'Audio track probe failed: $e');
    }
  }

  Future<void> _selectAudioTrack(String trackId) async {
    final handle = _playbackHandle;
    if (handle == null) return;
    try {
      await handle.selectAudioTrack(trackId);
      if (!mounted) return;
      setState(() => _selectedAudioTrackId = trackId);
    } catch (e) {
      AppLogger.w(
        'ExoTheaterScreen',
        'Failed to select audio track $trackId: $e',
      );
    }
  }

  String _audioPreview() {
    for (final t in _audioTracks) {
      if (t.id == _selectedAudioTrackId) {
        return TrackNameParser.parseAudio(
          title: t.label,
          language: t.language,
        ).mainTitle;
      }
    }
    return 'Audio Track';
  }

  List<SettingsTrackOption> _audioOptions() {
    return _audioTracks.map((t) {
      final parsed = TrackNameParser.parseAudio(
        title: t.label,
        language: t.language,
      );
      return SettingsTrackOption(
        mainTitle: parsed.mainTitle,
        subTitle: parsed.subTitle,
        selected: t.id == _selectedAudioTrackId,
        onSelect: () => unawaited(_selectAudioTrack(t.id)),
      );
    }).toList();
  }

  Future<void> _applySubtitleTrack(int? streamIndex) async {
    _subtitleContentTimer?.cancel();
    _subtitleContentTimer = null;

    setState(() {
      _selectedSubtitleIndex = streamIndex;
      _styledCues = [];
    });

    if (streamIndex == null) return;

    await _fetchAndApplySubtitleBytes(streamIndex);

    if (!_torrentController.isSubtitleTrackComplete(streamIndex)) {
      _subtitleContentTimer = Timer.periodic(const Duration(seconds: 20), (
        _,
      ) async {
        if (_selectedSubtitleIndex != streamIndex) {
          _subtitleContentTimer?.cancel();
          _subtitleContentTimer = null;
          return;
        }
        await _fetchAndApplySubtitleBytes(streamIndex);
        if (_torrentController.isSubtitleTrackComplete(streamIndex)) {
          _subtitleContentTimer?.cancel();
          _subtitleContentTimer = null;
        }
      });
    }
  }

  Future<void> _fetchAndApplySubtitleBytes(int streamIndex) async {
    final bytes = await _torrentController.fetchSubtitleBytes(
      streamIndex,
      kSubtitleFormat,
    );
    if (bytes == null) {
      AppLogger.w(
        'ExoTheaterScreen',
        'fetchSubtitleBytes returned null for track $streamIndex, format ${kSubtitleFormat.wireValue}',
      );
      return;
    }
    if (!mounted || _selectedSubtitleIndex != streamIndex) return;

    AppLogger.i(
      'ExoTheaterScreen',
      'Fetched ${bytes.length} bytes for track $streamIndex, format ${kSubtitleFormat.wireValue}',
    );

    try {
      final cues = await NativeSubtitleParser.parse(bytes, kSubtitleFormat);
      if (!mounted || _selectedSubtitleIndex != streamIndex) return;
      AppLogger.i(
        'ExoTheaterScreen',
        'Parsed ${cues.length} styled cues from ${kSubtitleFormat.wireValue}',
      );
      setState(() => _styledCues = cues);
    } catch (e) {
      AppLogger.w('ExoTheaterScreen', 'Native subtitle parse failed: $e');
    }
  }

  String _subtitlePreview() {
    final selected = _selectedSubtitleIndex;
    if (selected == null) return 'Off';
    for (final t in _torrentController.subtitleTracks) {
      if (t.streamIndex == selected) return t.label;
    }
    return 'Off';
  }

  List<SettingsTrackOption> _subtitleOptions() {
    return [
      SettingsTrackOption(
        mainTitle: 'Off',
        selected: _selectedSubtitleIndex == null,
        onSelect: () => unawaited(_applySubtitleTrack(null)),
      ),
      for (final t in _torrentController.subtitleTracks)
        SettingsTrackOption(
          mainTitle: t.label,
          selected: t.streamIndex == _selectedSubtitleIndex,
          onSelect: () => unawaited(_applySubtitleTrack(t.streamIndex)),
        ),
    ];
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _handleBackOrEscape();
      return true;
    }

    final handle = _playbackHandle;
    if (handle == null) return false;
    if (_isSettingsOpen || _torrentController.needsManualSelection) {
      return false;
    }

    switch (key) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        _controlsVisibility?.registerActivity();
        unawaited(handle.playOrPause());
        return true;

      case LogicalKeyboardKey.keyJ:
        _seekBy(handle, const Duration(seconds: -10));
        return true;
      case LogicalKeyboardKey.arrowLeft:
        if (_seekbarFocused) return false;
        _seekBy(handle, const Duration(seconds: -10));
        return true;

      case LogicalKeyboardKey.keyL:
        _seekBy(handle, const Duration(seconds: 10));
        return true;
      case LogicalKeyboardKey.arrowRight:
        if (_seekbarFocused) return false;
        _seekBy(handle, const Duration(seconds: 10));
        return true;

      case LogicalKeyboardKey.arrowUp:
        _adjustVolume(handle, 5);
        return true;
      case LogicalKeyboardKey.arrowDown:
        _adjustVolume(handle, -5);
        return true;

      case LogicalKeyboardKey.contextMenu:
        if (_torrentController.subtitleTracks.isEmpty) return false;
        _controlsVisibility?.registerActivity();
        setState(() => _isSettingsOpen = !_isSettingsOpen);
        return true;
    }
    return false;
  }

  void _seekBy(PlaybackHandle handle, Duration delta) {
    _controlsVisibility?.registerActivity();
    final target = handle.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > handle.duration ? handle.duration : target);
    unawaited(handle.seek(clamped));
  }

  void _adjustVolume(PlaybackHandle handle, double delta) {
    _controlsVisibility?.registerActivity();
    final newVolume = (handle.volume + delta).clamp(0.0, 100.0);
    unawaited(handle.setVolume(newVolume));
    if (newVolume > 0) {
      unawaited(
        SharedPreferencesAsync().setDouble('theater_volume', newVolume),
      );
    }
  }

  bool _closeSettingsIfOpen() {
    if (!_isSettingsOpen) return false;
    setState(() => _isSettingsOpen = false);
    return true;
  }

  void _handleBackOrEscape() {
    _controlsVisibility?.registerActivity();
    if (_closeSettingsIfOpen()) return;
    if (_torrentController.needsManualSelection) {
      unawaited(_exitTheater());
      return;
    }
    unawaited(Navigator.maybePop(context));
  }

  void _handleBackgroundTap() {
    if (!_videoInitialized) return;
    final cv = _controlsVisibility;
    if (cv == null) return;
    if (_closeSettingsIfOpen()) {
      cv.registerActivity();
      return;
    }
    if (cv.visible.value) {
      cv.hideNow();
    } else {
      cv.registerActivity();
    }
  }

  Future<void> _exitTheater() async {
    if (_isClosing) return;
    _isClosing = true;

    if (Platform.isAndroid || Platform.isIOS) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    if (mounted) Navigator.pop(context);
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

    _controlsVisibility?.dispose();
    _torrentController.removeListener(_onTorrentStateChanged);
    _torrentController.dispose();
    unawaited(_videoController?.dispose() ?? Future<void>.value());
    _playbackHandle?.dispose();
    _subtitleContentTimer?.cancel();
    _autoSkipController.dispose();
    _tracker.dispose();
    _topNotificationController.dispose();
    unawaited(_posSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Widget _buildControlsOverlay() {
    final cv = _controlsVisibility!;
    return ValueListenableBuilder<bool>(
      valueListenable: cv.visible,
      builder: (context, showControls, child) => AnimatedOpacity(
        opacity: showControls ? 1.0 : 0.0,
        duration: perfDuration(
          _uiPerformanceMode,
          const Duration(milliseconds: 300),
        ),
        child: IgnorePointer(ignoring: !showControls, child: child),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 24 + MediaQuery.paddingOf(context).top,
            left: 16,
            child: TheaterTopBar(
              title: 'Episode ${widget.episode}',
              uiPerformanceMode: _uiPerformanceMode,
              onBack: _exitTheater,
              onRestart: () => {}, //temporary(?) fix to stop lint
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: MobileTheaterControls(
              playback: _playbackHandle!,
              chapterMetadata: _chapters,
              uiPerformanceMode: _uiPerformanceMode,
              onInteract: cv.registerActivity,
              onInteractionStart: cv.beginInteraction,
              onInteractionEnd: cv.endInteraction,
              isSettingsOpen: _isSettingsOpen,
              onToggleSettings:
                  (_torrentController.subtitleTracks.isEmpty &&
                      _audioTracks.isEmpty)
                  ? null
                  : () {
                      cv.registerActivity();
                      setState(() => _isSettingsOpen = !_isSettingsOpen);
                    },
              onSeekbarFocusChange: (f) => _seekbarFocused = f,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;
    final handle = _playbackHandle;

    final staticLayer = Stack(
      fit: StackFit.expand,
      children: [
        if (_videoInitialized && videoController != null)
          RepaintBoundary(
            child: Center(
              child: AspectRatio(
                aspectRatio: videoController.value.aspectRatio,
                child: VideoPlayer(videoController),
              ),
            ),
          ),

        if (_videoInitialized &&
            videoController != null &&
            _styledCues.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: videoController,
              builder: (context, value, _) => StyledSubtitleView(
                cues: _styledCues,
                position: value.position,
                reservedBottom: 10,
              ),
            ),
          ),

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

        if (!_videoInitialized)
          ListenableBuilder(
            listenable: _torrentController,
            builder: (context, _) {
              if (_playerError != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _playerError!,
                      style: const TextStyle(color: AppPalette.statusCancelled),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (_torrentController.needsManualSelection) {
                return BatchEpisodePickerOverlay(
                  files: _torrentController.batchFiles,
                  requestedEpisode: widget.episode,
                  onSelect: _torrentController.selectBatchFile,
                  onBack: _exitTheater,
                );
              }
              return TheaterLoadingOverlay(
                title: 'Episode ${widget.episode}',
                controller: _torrentController,
              );
            },
          ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_closeSettingsIfOpen()) return;
        unawaited(_exitTheater());
      },
      child: Scaffold(
        backgroundColor: AppPalette.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleBackgroundTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              staticLayer,
              if (_videoInitialized && handle != null) _buildControlsOverlay(),
              if (_isSettingsOpen)
                Positioned(
                  bottom: 130,
                  right: 16,
                  child: TheaterSettingsMenu(
                    uiPerformanceMode: _uiPerformanceMode,
                    onClose: () => setState(() => _isSettingsOpen = false),
                    subtitlePreview: _subtitlePreview(),
                    subtitleOptions: _subtitleOptions(),
                    audioPreview: _audioTracks.isEmpty ? null : _audioPreview(),
                    audioOptions: _audioTracks.isEmpty ? null : _audioOptions(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
