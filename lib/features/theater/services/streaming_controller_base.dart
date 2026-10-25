import 'package:flutter/foundation.dart';

import 'native_subtitle_parser.dart';

/// A single video file inside a batch (multi-episode) torrent.
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

/// One embedded subtitle track from the Go server's
/// `GET /api/stream/:id/subtitles`; field names match its JSON. Only the
/// remote controller populates it (ARCHITECTURE.md § 10).
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

  /// Best-effort label; simpler than TrackNameParser's media_kit track naming.
  String get label {
    if (title != null && title!.trim().isNotEmpty) return title!;
    if (language != null && language!.trim().isNotEmpty) {
      return language!.toUpperCase();
    }
    return 'Track $streamIndex';
  }
}

/// Contract implemented by [StreamingController] (on-device libtorrent) and
/// [RemoteStreamingController] (Go server); the theater screens depend only
/// on it. See ARCHITECTURE.md § 5.
abstract class BaseStreamingController extends ChangeNotifier {
  /// Human-readable status shown in the loading overlay.
  String get statusText;

  /// URL handed to the active player once ready: loopback in local mode, the
  /// server's `/api/stream/<id>/video` in server mode.
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

  // No-op defaults: only RemoteStreamingController can extract subtitles.

  /// True once [fetchSubtitleTracks] is meaningful to call; false by default.
  bool get subtitlesAvailable => false;

  /// Embedded tracks of the active file; empty until fetched or if unsupported.
  List<RemoteSubtitleTrack> get subtitleTracks => const [];

  /// Fetches the track list; no-op where subtitles are unsupported.
  Future<void> fetchSubtitleTracks() async {}

  /// A track's current WebVTT, or null on failure or if unsupported. Content
  /// grows across calls while the file downloads ([isSubtitleTrackComplete]).
  Future<String?> fetchSubtitleContent(int streamIndex) async => null;

  /// True once this track's last fetch returned final content, so re-fetching
  /// is pointless. Defaults to true where subtitles are unsupported.
  bool isSubtitleTrackComplete(int streamIndex) => true;

  /// A track's raw bytes in [format] for [NativeSubtitleParser], with the same
  /// growing-file semantics as [fetchSubtitleContent]. Null on failure or if
  /// unsupported.
  Future<Uint8List?> fetchSubtitleBytes(
    int streamIndex,
    NativeSubtitleFormat format,
  ) async => null;
}
