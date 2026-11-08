import 'package:flutter/material.dart';

import '../../data/anilist/models/anime.dart';
import '../../features/theater/services/streaming_controller_base.dart';
import '../../features/theater/theater_screen.dart';

/// Runs [TheaterScreen] for one custom-magnet session, re-pushing it with the
/// buffered controller and resume position after each
/// [TheaterRestartRequest]; returns once the user exits. See
/// ARCHITECTURE.md § 9.
///
/// [anime]/[episode] are both null for a custom magnet; [displayTitle] then
/// replaces "Episode N" in the top bar.
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

    // Any non-restart result exits; a next-episode request needs episode
    // context, which this helper never has.
    break;
  }
}