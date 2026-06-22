import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_service.dart';
import '../../data/torrent/models/torrent.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/anilist/anilist_tracker_service.dart';
import '../../shared/widgets/toast.dart';
import 'services/streaming_controller_service.dart';
import 'services/theater_data.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_controls.dart';
import 'widgets/theater_settings.dart';
import 'widgets/theater_batch_picker.dart';

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
  late final StreamingController _torrentController;
  late final AnilistTrackerService _tracker;

  late final Player _player;
  late final VideoController _videoController;

  final FocusNode _focusNode = FocusNode();
  bool _videoInitialized = false;
  bool _showControls = true;
  bool _isSettingsOpen = false;
  bool _isFullscreen = false;
  Timer? _hideControlsTimer;
  bool _isClosing = false;

  // ── AUTOSKIP STATE ──
  bool _autoSkip = false;
  bool _isAutoSkipping = false;
  Chapter? _currentAutoSkipChapter;
  Timer? _autoSkipTimer;

  // ── INDEPENDENT PERFORMANCE SETTINGS ──
  bool _uiPerformanceMode = false;
  String _videoFilterQuality = 'low';

  List<Chapter> _chapters = [];
  StreamSubscription? _posSub;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(libass: true));
    _videoController = VideoController(_player);
    _torrentController = StreamingController();
    _torrentController.addListener(_onTorrentStateChanged);

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

    SettingsService().load().then((s) {
      if (mounted) {
        setState(() {
          _uiPerformanceMode = s.uiPerformanceMode;
          _videoFilterQuality = s.videoFilterQuality;
          _autoSkip = s.autoSkip;
        });
      }
    });

    _initPlayerAndStream();
    _startHideControlsTimer();
  }

  Future<void> _initPlayerAndStream() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final hwdec = prefs.getString(SettingsService.kHwDec) ?? 'auto';
    final androidHwDec =
        prefs.getString(SettingsService.kAndroidHwDec) ?? 'mediacodec-copy';

    final platform = _player.platform;
    if (platform is NativePlayer) {
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
    }

    _torrentController.initialize(
      widget.torrent.magnetLink,
      episodeNumber: widget.episode,
    );

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
          debugPrint('⏭Executing skip to: ${activeChapter!.end}');
          _player.seek(activeChapter!.end);
          _isAutoSkipping = false;
        }
      });
    }
  }

  void _onTorrentStateChanged() {
    if (_torrentController.isReadyToPlay && !_videoInitialized) {
      setState(() => _videoInitialized = true);
      _player.open(Media(_torrentController.streamUrl!));

      _player.stream.duration.firstWhere((d) => d > Duration.zero).then((
        _,
      ) async {
        final resolvedChapters = await loadChapters(_player);

        // ── LOGGING TO INSPECT MKV CHAPTERS ──
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
      } else {
        _exitTheater();
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

  @override
  void dispose() {
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    _autoSkipTimer?.cancel();
    _posSub?.cancel();
    _torrentController.removeListener(_onTorrentStateChanged);
    _tracker.dispose();
    if (!_isClosing) {
      _isClosing = true;
      Future.microtask(_disposePlaybackResources);
    }
    super.dispose();
  }

  FilterQuality _getFilterQuality() {
    switch (_videoFilterQuality) {
      case 'high':
        return FilterQuality.high;
      case 'medium':
        return FilterQuality.medium;
      case 'none':
        return FilterQuality.none;
      case 'low':
      default:
        return FilterQuality.low;
    }
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
                        return _torrentController.isReadyToPlay
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
