import 'package:flutter/material.dart';

import '../../data/anilist/models/anime.dart';
import '../../features/theater/services/streaming_controller_base.dart';
import '../../features/theater/theater_screen.dart';

/// Pushes [TheaterScreen] for a single viewing session, re-pushing a
/// fresh instance whenever it pops with a [TheaterRestartRequest]
/// instead of a genuine exit (see that class's doc comment for what
/// triggers this — a freeze-recovery restart or a Libass toggle) —
/// carrying the still-buffered [BaseStreamingController] and a resume
/// position forward so a restart never re-downloads the torrent from
/// scratch. Returns once the user backs all the way out (a genuine
/// `null` pop).
///
/// Deliberately scoped to restarts only: a [TheaterNextEpisodeRequest]
/// never reaches this helper, because this helper is only ever used for
/// sessions with no episode context to advance from in the first place
/// (see [anime]/[episode] below) — `TheaterScreen` itself never produces
/// that request when `anime`/`episode`/`totalEpisodes` are null (see its
/// constructor assertion). The from-AnimeDetails path, which does have
/// next-episode autoplay, drives `TheaterScreen` directly with its own
/// loop (`AnimeDetailsScreen._streamTorrent`) instead of going through
/// this helper.
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
    final result = await Navigator.push<TheaterExitResult?>(
      context,
      MaterialPageRoute<TheaterExitResult?>(
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

    if (result is TheaterRestartRequest) {
      resumeController = result.resumeController;
      resumePosition = result.resumePosition;
      continue;
    }

    // A genuine `null` (normal exit) or, in principle, a
    // TheaterNextEpisodeRequest — the latter never actually happens here
    // per the class doc above, but is handled the same as `null` (stop
    // looping) rather than asserting, since crashing this helper over an
    // invariant enforced elsewhere would be a worse failure mode than
    // just exiting.
    break;
  }
}
