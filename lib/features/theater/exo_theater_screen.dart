import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../data/anilist/models/anime.dart';
import '../../data/torrent/models/torrent.dart';
import 'services/native_subtitle_parser.dart';
import 'services/remote_streaming_controller.dart';
import 'services/streaming_controller.dart';
import 'services/streaming_controller_base.dart';
import 'widgets/batch_picker.dart';
import 'widgets/seekbar.dart';
import 'widgets/styled_subtitle_view.dart';
import 'widgets/theater_player.dart';

// ── Branch-experiment screen, reachable in production via the
// "Experimental Video Engine" toggle (Settings → Playback Preferences,
// mobile/TV only — see settings_menu.dart), which maps to
// AppSettings.useExperimentalPlayer. That flag defaults to false, so
// TheaterScreen is still what every session gets unless a user opts in
// — this remains a branch experiment in spirit, just no longer an
// unreachable one. ──
//
// Tests one specific, isolated hypothesis from the media_kit-vs-ExoPlayer
// discussion: does swapping the actual decode/render engine fix the
// stutter/crashes we see on weak Android TV boxes? Deliberately NOT a
// feature-complete TheaterScreen replacement — no chapters, no auto-skip,
// no AniList tracking, no keyboard shortcuts, no fullscreen chrome
// handling. Those are all orthogonal to the thing being tested and would
// multiply the diff for zero diagnostic value on THIS question. The
// Settings toggle's own subtitle warns users about this trade-off.
//
// What IS reused, deliberately, because it's unrelated to the hypothesis
// and already works: the real torrent/server streaming flow
// (StreamingController / RemoteStreamingController just resolve a
// streamUrl — see the chat notes on why that layer is engine-agnostic),
// the batch picker overlay, and the loading overlay. Only the final
// player widget is swapped.
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

// Approximate on-screen height of the bottom controls (Seekbar +
// TheaterTopBar-equivalent chrome for this screen). Previously just a
// bare `110` baked into StyledSubtitleView's own Positioned bounds; now
// named and passed down explicitly (see StyledSubtitleView's
// reservedBottom) so the widget can be measured against the video's
// true full height — required for Cue.line/Cue.position fractions to
// resolve correctly — while still keeping cues clear of this zone.
const double kSubtitleControlsReservedHeight = 110;

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

  bool _videoInitialized = false;
  String? _playerError;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

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
    // ── initState can't be async — _initStreamAndPlayer() returns
    // Future<void>, so the fire-and-forget intent is made explicit
    // instead of silently dropped (unawaited_futures). ──
    unawaited(_initStreamAndPlayer());
  }

  // ── Mirrors TheaterScreen._initPlayerAndStream's controller-selection
  // logic exactly (local vs remote-server mode) — same real streaming
  // path, so whatever TV box you're testing against sees the same
  // magnet-to-buffer behavior it would in production. ──
  Future<void> _initStreamAndPlayer() async {
    if (!mounted) return;
    final s = SettingsScope.of(context, listen: false).settings;

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
      _openVideoPlayer(_torrentController.streamUrl!);
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
    // ── viewType is a top-level named param on the constructor itself —
    // NOT nested inside VideoPlayerOptions (that class is for things
    // like mixWithOthers). Verified directly against the current
    // video_player API docs rather than assumed from memory, since this
    // is the one line the whole experiment hinges on. ──
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

    controller.addListener(_onVideoTick);
    await controller.play();

    setState(() {
      _videoController = controller;
      _videoInitialized = true;
      _duration = controller.value.duration;
    });
  }

  void _onVideoTick() {
    final c = _videoController;
    if (c == null || !mounted) return;
    final v = c.value;
    final bufferedEnd = v.buffered.isEmpty
        ? Duration.zero
        : v.buffered.last.end;

    setState(() {
      _position = v.position;
      _duration = v.duration;
      _buffer = bufferedEnd;
    });
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

  Widget _buildSubtitleButton() {
    final tracks = _torrentController.subtitleTracks;
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Material(
      color: AppPalette.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: PopupMenuButton<int?>(
        tooltip: 'Subtitles',
        icon: Icon(
          _selectedSubtitleIndex == null
              ? Icons.subtitles_off_outlined
              : Icons.subtitles_outlined,
          color: AppPalette.white,
        ),
        onSelected: (streamIndex) =>
            unawaited(_applySubtitleTrack(streamIndex)),
        itemBuilder: (context) => [
          CheckedPopupMenuItem<int?>(
            value: null,
            checked: _selectedSubtitleIndex == null,
            child: const Text('Off'),
          ),
          for (final t in tracks)
            CheckedPopupMenuItem<int?>(
              value: t.streamIndex,
              checked: _selectedSubtitleIndex == t.streamIndex,
              child: Text(t.label),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _torrentController.removeListener(_onTorrentStateChanged);
    _torrentController.dispose();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _subtitleContentTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;

    return Scaffold(
      backgroundColor: AppPalette.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_videoInitialized && videoController != null)
            GestureDetector(
              onTap: () => videoController.value.isPlaying
                  ? videoController.pause()
                  : videoController.play(),
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
          if (_videoInitialized && videoController != null && _styledCues.isNotEmpty)
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
                  reservedBottom: kSubtitleControlsReservedHeight,
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
                        style: const TextStyle(
                          color: AppPalette.statusCancelled,
                        ),
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
                    onBack: () => Navigator.of(context).pop(),
                  );
                }
                return TheaterLoadingOverlay(
                  episode: widget.episode,
                  controller: _torrentController,
                );
              },
            ),

          Positioned(
            top: 24 + MediaQuery.paddingOf(context).top,
            left: 24,
            child: TheaterTopBar(
              episode: widget.episode,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),

          // ── Subtitles (added): only appears once at least one track
          // has actually been fetched — ListenableBuilder so it shows up
          // live the moment fetchSubtitleTracks() resolves, without
          // needing its own separate state tracking here. ──
          Positioned(
            top: 24 + MediaQuery.paddingOf(context).top,
            right: 24,
            child: ListenableBuilder(
              listenable: _torrentController,
              builder: (context, _) => _buildSubtitleButton(),
            ),
          ),

          if (_videoInitialized && videoController != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppPalette.black.withValues(alpha: 0.9),
                      AppPalette.transparent,
                    ],
                  ),
                ),
                // ── Reusing the real Seekbar widget, not a rebuilt one —
                // its constructor only takes plain Duration values and
                // callbacks, it was never actually coupled to media_kit's
                // Player type, so it works unmodified against
                // video_player's position/duration/buffer instead. ──
                child: Seekbar(
                  position: _position,
                  duration: _duration,
                  buffer: _buffer,
                  chapters: const [],
                  uiPerformanceMode: false,
                  onSeek: videoController.seekTo,
                  onSeekStart: () {},
                  onSeekEnd: () {},
                ),
              ),
            ),
        ],
      ),
    );
  }
}