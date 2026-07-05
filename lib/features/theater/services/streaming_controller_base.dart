import 'package:flutter/foundation.dart';

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

/// Common interface implemented by both:
///  • [StreamingController]       — runs libtorrent_flutter on-device
///  • [RemoteStreamingController] — delegates to the AniStream Go server
///
/// [TheaterScreen] only talks to this contract, so it never needs to know
/// which mode is active.
abstract class BaseStreamingController extends ChangeNotifier {
  /// Human-readable status shown in the loading overlay.
  String get statusText;

  /// The URL handed to media_kit once the stream is ready.
  /// Local mode: http://127.0.0.1:\<port\>/...
  /// Server mode: http://\<server-ip\>:7878/api/stream/\<id\>/video
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
}
