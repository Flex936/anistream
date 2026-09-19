import 'package:flutter/foundation.dart';

import 'native_subtitle_parser.dart';

/// A single video file inside a batch (multi-episode) torrent.
///
/// Defined here rather than in [StreamingController] so that
/// [RemoteStreamingController] and [BatchEpisodePickerOverlay] can reference
/// it without creating a circular dependency.
class BatchFileOption {
  final int index;
  final String name;
  final int size;
  final int? guessedEpisode;

  const BatchFileOption({
    required this.index,
    required this.name,
    required this.size,
    this.guessedEpisode,
  });
}

/// Metadata for one embedded subtitle track, as reported by the AniStream
/// Go server's `GET /api/stream/:id/subtitles` endpoint. Field names match
/// that endpoint's JSON shape directly (see anistream_server's
/// subtitle_extractor.go).
///
/// Only ever populated via [RemoteStreamingController] today — the
/// on-device libtorrent path has no subtitle-extraction step of its own;
/// that would need either a native Media3 bridge that probes and demuxes
/// a local file directly, or a ported MKV-subtitle parser, neither of
/// which exists yet.
class RemoteSubtitleTrack {
  final int streamIndex;
  final String codec;
  final String? language;
  final String? title;

  const RemoteSubtitleTrack({
    required this.streamIndex,
    required this.codec,
    this.language,
    this.title,
  });

  factory RemoteSubtitleTrack.fromJson(Map<String, dynamic> json) =>
      RemoteSubtitleTrack(
        streamIndex: (json['streamIndex'] as num).toInt(),
        codec: json['codec'] as String? ?? 'unknown',
        language: json['language'] as String?,
        title: json['title'] as String?,
      );

  /// Best-effort human-readable label — deliberately simple (not the full
  /// TrackNameParser treatment media_kit tracks get on the desktop/mpv
  /// path) since this is a newer, still-evolving path. Worth unifying
  /// with TrackNameParser's naming conventions later if this graduates
  /// past validation.
  String get label {
    if (title != null && title!.trim().isNotEmpty) return title!;
    if (language != null && language!.trim().isNotEmpty) {
      return language!.toUpperCase();
    }
    return 'Track $streamIndex';
  }
}

/// Common interface implemented by both:
///  • [StreamingController]       — runs libtorrent_flutter on-device
///  • [RemoteStreamingController] — delegates to the AniStream Go server
///
/// [TheaterScreen] and [ExoTheaterScreen] only talk to this contract, so
/// neither needs to know which mode is active.
abstract class BaseStreamingController extends ChangeNotifier {
  /// Human-readable status shown in the loading overlay.
  String get statusText;

  /// The URL handed to whichever player is active once the stream is
  /// ready — media_kit, or video_player on the ExoPlayer path.
  /// Local mode: `http://127.0.0.1:<port>/...`
  /// Server mode: `http://<server-ip>:7878/api/stream/<id>/video`
  String? get streamUrl;

  /// True once enough data has been buffered to hand the URL to the player.
  bool get isReadyToPlay;

  /// True if an unrecoverable error occurred.
  bool get hasError;

  /// True when the torrent contains multiple episodes and the user must pick.
  bool get needsManualSelection;

  /// Files to display in [BatchEpisodePickerOverlay].
  List<BatchFileOption> get batchFiles;

  /// Start the download / connect to the server and begin buffering.
  Future<void> initialize(String magnetUri, {int? episodeNumber});

  /// Called when the user picks a file from the batch picker.
  void selectBatchFile(int fileIndex);

  // Concrete (non-abstract) with no-op defaults rather than added to the
  // abstract contract above — StreamingController (on-device) has no
  // subtitle-extraction path yet, and forcing it to implement a feature
  // it structurally can't support yet would be worse than just defaulting
  // to "not available" until that changes.

  /// True once subtitle tracks can be queried — i.e. [fetchSubtitleTracks]
  /// is meaningful to call. Defaults to false; only
  /// [RemoteStreamingController] currently overrides it.
  bool get subtitlesAvailable => false;

  /// Embedded subtitle tracks found in the active file, once fetched via
  /// [fetchSubtitleTracks]. Empty until then, and always empty on
  /// controllers that don't support subtitles at all.
  List<RemoteSubtitleTrack> get subtitleTracks => const [];

  /// Fetches the subtitle track list from wherever this controller's data
  /// source is. No-op on controllers that don't support subtitles.
  Future<void> fetchSubtitleTracks() async {}

  /// Fetches a subtitle track's current WebVTT content. While the
  /// underlying file is still downloading, repeated calls can return
  /// progressively more content each time — see [isSubtitleTrackComplete]
  /// to know when it's no longer worth calling again. Returns null on
  /// failure or if this controller doesn't support subtitles at all.
  Future<String?> fetchSubtitleContent(int streamIndex) async => null;

  /// True once [fetchSubtitleContent] for this track is known to have
  /// returned its final content — i.e. further calls won't return
  /// anything new, so it's safe to stop re-fetching. Defaults to true
  /// (the safe "don't bother retrying" answer) on controllers that don't
  /// support subtitles, or for a track that's never been fetched.
  bool isSubtitleTrackComplete(int streamIndex) => true;

  /// Fetches a subtitle track's raw bytes in [format] — the
  /// native-parser counterpart to [fetchSubtitleContent], which only
  /// ever returns WebVTT text for video_player's Dart-side
  /// ClosedCaptionFile mechanism. Consumed by [NativeSubtitleParser] to
  /// get real timing, positioning, and per-run styling out of Media3's
  /// own TtmlParser/SsaParser — see ExoTheaterScreen. Same growing-file
  /// semantics as [fetchSubtitleContent] apply: while the underlying
  /// file is still downloading, repeated calls can return progressively
  /// more complete bytes — see [isSubtitleTrackComplete]. Returns null
  /// on failure or if this controller doesn't support subtitles at all.
  Future<Uint8List?> fetchSubtitleBytes(
    int streamIndex,
    NativeSubtitleFormat format,
  ) async => null;
}