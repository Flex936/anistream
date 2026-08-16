import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/torrent/models/torrent.dart';
import '../../shared/utils/perf_animations.dart';
import '../../shared/widgets/toast.dart';
import 'services/auto_skip_controller.dart';
import 'services/controls_visibility_controller.dart';
import 'services/native_chapter_parser.dart';
import 'services/native_subtitle_parser.dart';
import 'services/playback_handle.dart';
import 'services/remote_streaming_controller.dart';
import 'services/streaming_controller.dart';
import 'services/streaming_controller_base.dart';
import 'services/theater_data.dart';
import 'widgets/batch_picker.dart';
import 'widgets/mobile_theater_controls.dart';
import 'widgets/styled_subtitle_view.dart';
import 'widgets/theater_player.dart';
import 'widgets/theater_settings.dart';

// Branch-experiment screen, reachable in production via the
// "Experimental Video Engine" toggle (Settings → Playback Preferences,
// mobile/TV only — see settings_menu.dart), which maps to
// AppSettings.useExperimentalPlayer. That flag defaults to false, so
// TheaterScreen is still what every session gets unless a user opts in
// — this remains a branch experiment in spirit, just no longer an
// unreachable one.
//
// Tests one specific, isolated hypothesis from the media_kit-vs-ExoPlayer
// discussion: does swapping the actual decode/render engine fix the
// stutter/crashes we see on weak Android TV boxes? The player widget
// itself stays the isolated part of that test — AniList tracking is
// still out of scope, and D-Pad/TV-remote focus navigation is a
// separate, not-yet-started piece of work. Chapters and auto-skip ARE
// wired up (see the "Chapters + auto-skip" section below) via Media3's
// own Chapter metadata support rather than anything torrent/server-side
// — media_kit/mpv gets chapters natively from whatever stream it's
// given, but video_player exposes no such thing, so
// ChapterMetadataPlugin reads them directly off the container the same
// stream URL points at, working identically in local and server-mode
// streaming. Everything else — a full mobile-oriented control bar
// (MobileTheaterControls), auto-hide-on-inactivity,
// background-tap-to-toggle, keyboard shortcuts, and immersive system UI
// + landscape lock on enter/exit — matches TheaterScreen's own behavior,
// sharing SkipChip, Seekbar, and TheaterSettingsMenu with it directly
// instead of duplicating them.
//
// ── The kUseHardwareOverlay flag — this is the actual experiment ──
//
// Stage 1 (false, the default below): plain video_player on its default
// TextureView-backed path. Tests whether ExoPlayer's own MediaCodec
// device-workaround tables alone fix the crashes we see — independent of
// the hardware-overlay question entirely. This is the safe, "recommended"
// configuration; run this stage first on your worst TV boxes.
//
// Stage 2 (flip to true): forces VideoViewType.platformView, which is
// the only way to get a real SurfaceView — and therefore a hardware
// overlay — inside a Flutter widget tree. IMPORTANT, found while writing
// this: video_player_android's own package page states platform-view
// mode is "not currently recommended on Android due to a known issue,"
// and there's an open Flutter issue (#164899) about platform-view video
// drawing on top of other UI in certain scrollable layouts. Our case is
// always fullscreen with nothing scrolling behind it, which is narrower
// than the reported bug — but go into Stage 2 knowing you're flipping on
// something the Flutter team itself is still shaking out, not something
// we're doing wrong if it glitches.
//
// Testing (Stage 1 alone) already confirmed the actual fix: real,
// measured VO-stage frame drops on the media_kit path, decoder-stage
// drops at zero. Stage 2 was never touched to get that result — nothing
// here currently exercises the hardware-overlay path, on purpose.
const bool kUseHardwareOverlay = false;

// ── Subtitle pipeline (added) ──────────────────────────────────────────
//
// Which format gets requested from the server and handed to Media3's
// native parser (see SubtitleParserPlugin.kt / native_subtitle_parser.dart).
// ass is the default: the source track inside the MKV is already ASS for
// the overwhelming majority of fansub releases, so the server serves it
// via a stream copy — no re-encode — and Media3's SsaParser decodes it
// with real timing, positioning, and style-span fidelity.
//
// Swapping to TTML is exactly flipping this one value to
// NativeSubtitleFormat.ttml. Nothing else here, in
// remote_streaming_controller.dart, or in SubtitleParserPlugin.kt
// branches on format beyond this same enum — the server converts via
// go-astisub (not ffmpeg — see subtitle_extractor.go's FormatTTML doc
// comment for why) and the native side swaps SsaParser for TtmlParser.
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

  // Only constructed once _playbackHandle exists (see _openVideoPlayer)
  // — there's nothing to auto-hide/show before the video is ready
  // anyway, since the loading/batch-picker overlay occupies that time
  // instead of the controls overlay.
  ControlsVisibilityController? _controlsVisibility;

  bool _videoInitialized = false;
  String? _playerError;

  bool _isSettingsOpen = false;
  bool _isClosing = false;
  bool _uiPerformanceMode = false;

  // Set by MobileTheaterControls via onSeekbarFocusChange. Read only by
  // _onKeyEvent, never by build(), so a plain field write (no setState)
  // is correct and cheap — mirrors theater_screen.dart's identical
  // _seekbarFocused field and the same double-seek concern it guards
  // against.
  bool _seekbarFocused = false;

  // ── Chapters + auto-skip (added) ────────────────────────────────────
  //
  // Fetched once per session via ChapterMetadataPlugin.kt, which reads
  // Media3's own Chapter metadata entries off a throwaway ExoPlayer
  // pointed at the same stream URL the real player opens — see
  // _fetchChapters. AutoSkipController itself is player-engine-agnostic
  // (it only needs a seek callback), so this is the same class
  // TheaterScreen uses, just wired to PlaybackHandle.seek instead of
  // media_kit's Player.seek directly.
  late final AutoSkipController _autoSkipController;
  bool _autoSkip = false;
  List<Chapter> _chapters = [];
  StreamSubscription<Duration>? _posSub;

  // ── Subtitles (added) ────────────────────────────────────────────────
  int? _selectedSubtitleIndex;
  bool _subtitleFetchTriggered = false;
  bool _subtitleAutoApplied = false;
  // Parsed cues for the currently-selected track — see
  // _fetchAndApplySubtitleBytes and StyledSubtitleView. Replaces the old
  // WebVTTCaptionFile/setClosedCaptionFile flow entirely: cues now carry
  // real timing, positioning, and per-run styling from Media3's own
  // TtmlParser/SsaParser instead of video_player's plain-text captions.
  List<StyledCue> _styledCues = [];
  // Re-fetches the selected track's content periodically while the
  // server hasn't yet marked it complete — see _applySubtitleTrack.
  Timer? _subtitleContentTimer;

  @override
  void initState() {
    super.initState();
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

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    // onSeek defers to whatever _playbackHandle currently is rather than
    // capturing it at construction time — this runs before
    // _openVideoPlayer has ever created one. AutoSkipController itself
    // never calls onSeek before chapters exist, and chapters are only
    // ever set once _playbackHandle is already non-null (see
    // _fetchChapters), so the null-coalescing here is a defensive
    // fallback, not a path expected to actually run.
    _autoSkipController = AutoSkipController(
      onSeek: (position) => _playbackHandle?.seek(position) ?? Future.value(),
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

    // initState can't be async — _initStreamAndPlayer() returns
    // Future<void>, so the fire-and-forget intent is made explicit
    // instead of silently dropped (unawaited_futures).
    unawaited(_initStreamAndPlayer());
  }

  // Mirrors TheaterScreen._initPlayerAndStream's controller-selection
  // logic exactly (local vs remote-server mode) — same real streaming
  // path, so whatever TV box you're testing against sees the same
  // magnet-to-buffer behavior it would in production.
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
    _torrentController.initialize(
      widget.torrent.magnetLink,
      episodeNumber: widget.episode,
    );
  }

  void _onTorrentStateChanged() {
    if (_torrentController.isReadyToPlay && _videoController == null) {
      unawaited(_openVideoPlayer(_torrentController.streamUrl!));
    }

    // ── Subtitles (added). Both guards below are one-shot triggers —
    // _onTorrentStateChanged fires on every unrelated change too (buffer
    // percentage ticks, etc.), so without _subtitleFetchTriggered /
    // _subtitleAutoApplied this would re-call fetchSubtitleTracks() or
    // re-apply the first track on every single notification once the
    // relevant condition is first met. ──
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
    // viewType is a top-level named param on the constructor itself —
    // NOT nested inside VideoPlayerOptions (that class is for things
    // like mixWithOthers). Verified directly against the current
    // video_player API docs rather than assumed from memory, since this
    // is the one line the whole engine experiment hinges on.
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      viewType: kUseHardwareOverlay
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    );

    try {
      await controller.initialize();
    } catch (e) {
      controller.dispose();
      if (mounted) setState(() => _playerError = 'video_player failed: $e');
      return;
    }

    if (!mounted) {
      controller.dispose();
      return;
    }

    final handle = VideoPlayerPlaybackHandle(controller);

    // Shares TheaterScreen's exact 'theater_volume' preference key, so
    // a volume/mute choice made on either engine carries over to the
    // other the next time either one opens.
    final savedVolume =
        await SharedPreferencesAsync().getDouble('theater_volume') ?? 100.0;
    await handle.setVolume(savedVolume);

    await controller.play();

    if (!mounted) {
      handle.dispose();
      controller.dispose();
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

    // AutoSkipController needs position ticks the same way TheaterScreen
    // feeds it via _player.stream.position — nothing in this State
    // subscribed to position before now, since MobileTheaterControls'
    // own internal timeline (a separate State object) is the only other
    // position listener, and it doesn't expose ticks back up to here.
    _posSub = handle.positionStream.listen(_autoSkipController.onPosition);

    unawaited(_fetchChapters(url, handle));
  }

  // ── Chapters + auto-skip (added) ────────────────────────────────────
  //
  // ChapterMetadataPlugin.kt opens a throwaway ExoPlayer against [url]
  // purely to read whatever Chapter metadata entries Media3's own
  // extractors attach to the container — this is independent of
  // video_player's own player instance (there's no supported way to
  // reach into another plugin's internal ExoPlayer), so it necessarily
  // opens the stream a second time. Confirmed safe against
  // anistream-server's video endpoint, which already hands out an
  // independent reader per HTTP request for exactly this kind of
  // concurrent-range-request case.
  //
  // Deliberately fire-and-forget from _openVideoPlayer's perspective —
  // chapters are supplementary, not required for playback to start, the
  // same way subtitle fetching doesn't block anything above.
  Future<void> _fetchChapters(String url, PlaybackHandle handle) async {
    try {
      final raw = await NativeChapterParser.extractChapters(url);
      if (!mounted) return;

      // Chapter.isHidden() means "should not be shown in a table of
      // contents UI" per its own doc comment — SkipChip is exactly that
      // kind of UI, so hidden markers are dropped here rather than
      // reaching buildChaptersFromRaw at all.
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

  // ── Subtitles (added) ────────────────────────────────────────────────
  //
  // Fetches one track's raw bytes (ass, or ttml — see kSubtitleFormat)
  // through the controller and runs them through NativeSubtitleParser
  // (Media3's own TtmlParser/SsaParser via SubtitleParserPlugin.kt),
  // storing the resulting cues in state for StyledSubtitleView to render.
  // No longer routed through the video controller at all — unlike the
  // old setClosedCaptionFile flow, cue fetching/parsing is now
  // independent of whether the video player itself has finished
  // initializing, which also fixes a latent ordering gap the old code
  // had (a subtitle selection arriving before _videoController existed
  // was silently dropped).
  //
  // While the source file is still downloading, the server can return
  // progressively more content on each fetch (see
  // RemoteStreamingController.fetchSubtitleBytes's doc comment) — this
  // re-fetches on a timer until isSubtitleTrackComplete says there's no
  // point asking again. Cancels and restarts cleanly if the user picks a
  // different track mid-poll.
  //
  // streamIndex == null means "Off": just clear the cue list.
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
        // User switched tracks (or turned subtitles off) while this
        // timer was waiting — stop rather than clobbering their new
        // choice with stale content for the old track.
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
      // Distinguished from the mounted/track-changed guard below —
      // this specifically means the fetch itself failed (network error,
      // or the server rejected the format — e.g. ass/ttml requested
      // against a track that isn't actually ass/ssa, see
      // subtitle_extractor.go's IsNativeCodec).
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

  // Settings popup data (added). Builds the plain SettingsTrackOption
  // rows TheaterSettingsMenu renders from this controller's own
  // RemoteSubtitleTrack list — the mobile counterpart to
  // DesktopTheaterSettingsMenu's media_kit-Tracks version in
  // theater_settings.dart. No audio page: video_player exposes no
  // audio-track switching to offer one.
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

  // Keyboard shortcuts.
  //
  // Same shape as TheaterScreen's own _onKeyEvent, minus the pieces that
  // depend on features this screen doesn't have: no F/fullscreen key
  // (this screen has no toggleable windowed state to escape — see
  // initState/_exitTheater for the always-on immersive handling
  // instead), and no dpadModeActive gate (this screen doesn't wire
  // D-Pad focus at all, so there's no competing input scheme for these
  // keys to defer to). Chapters exist here now (see "Chapters +
  // auto-skip" above), but Shift+seek chapter-jump was never asked for
  // on this screen and isn't wired up — SkipChip covers the
  // skip-a-chapter case; nothing currently covers manual jump-to-chapter
  // outside of it. _seekbarFocused mirrors TheaterScreen's exact guard:
  // Seekbar keeps its own Focus.onKeyEvent for Left/Right when it holds
  // keyboard focus, so this handler defers to it instead of
  // double-seeking.
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
      // dispose() must stay synchronous, so these fire-and-forget calls
      // are wrapped explicitly instead of silently dropped
      // (unawaited_futures) — same reasoning as TheaterScreen's dispose().
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
    _videoController?.dispose();
    _playbackHandle?.dispose();
    _subtitleContentTimer?.cancel();
    _autoSkipController.dispose();
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
              episode: widget.episode,
              uiPerformanceMode: _uiPerformanceMode,
              onBack: _exitTheater,
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
              onToggleSettings: _torrentController.subtitleTracks.isEmpty
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

        // ── Subtitles (added): StyledSubtitleView reads _styledCues —
        // real timing, positioning, and per-run styling from Media3's
        // TtmlParser/SsaParser via NativeSubtitleParser — instead of
        // video_player's own plain-text-only ClosedCaption widget.
        // Spans the FULL video area, bottom:0 included — Cue.line/
        // Cue.position are fractions of the true video height (same
        // denominator ExoPlayer's own SubtitleView would use), so
        // measuring against a pre-shrunk area shifts every cue upward
        // from where the source file actually places it. Staying clear
        // of the controls bar is reservedBottom's job now, applied per
        // cue inside StyledSubtitleView, not this Positioned's own
        // bounds. Wrapped in its own ValueListenableBuilder
        // (VideoPlayerController IS a ValueNotifier<VideoPlayerValue>)
        // so only this small subtree rebuilds as playback position
        // changes, not the whole screen. ──
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
                //Subtitle Height
                reservedBottom: 10,
              ),
            ),
          ),

        if (_isSettingsOpen)
          Positioned(
            bottom: 200,
            right: 16,
            child: TheaterSettingsMenu(
              uiPerformanceMode: _uiPerformanceMode,
              onClose: () => setState(() => _isSettingsOpen = false),
              subtitlePreview: _subtitlePreview(),
              subtitleOptions: _subtitleOptions(),
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
                episode: widget.episode,
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
            ],
          ),
        ),
      ),
    );
  }
}