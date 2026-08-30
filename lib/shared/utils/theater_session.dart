import 'package:flutter/material.dart';

import '../../data/anilist/models/anime.dart';
import '../../features/theater/services/streaming_controller_base.dart';
import '../../features/theater/theater_screen.dart';

/// Pushes [TheaterScreen] for a single viewing session, re-pushing a
/// fresh instance whenever it pops with a [TheaterRestartRequest]
/// instead of a genuine exit (see that class's doc comment for what
/// triggers this) — carrying the still-buffered [BaseStreamingController]
/// and a resume position forward so a restart never re-downloads the
/// torrent from scratch. Returns once the user backs all the way out (a
/// genuine `null` pop).
///
/// [anime]/[episode] are both null for a custom-magnet stream with no
/// AniList context — see [TheaterScreen]'s own constructor assertion for
/// that invariant. [displayTitle] is what the top bar/loading overlay
/// show instead of "Episode N" in that case.
Future<void> runTheaterSession({
  required BuildContext context,
  Anime? anime,
  int? episode,
  required String magnetUri,
  String? displayTitle,
}) async {
  BaseStreamingController? resumeController;
  Duration? resumePosition;

  while (true) {
    final result = await Navigator.push<TheaterRestartRequest?>(
      context,
      MaterialPageRoute<TheaterRestartRequest?>(
        builder: (_) => TheaterScreen(
          anime: anime,
          episode: episode,
          magnetUri: magnetUri,
          displayTitle: displayTitle,
          resumeController: resumeController,
          resumePosition: resumePosition,
        ),
      ),
    );

    if (result == null) break;
    resumeController = result.resumeController;
    resumePosition = result.resumePosition;
  }
}
