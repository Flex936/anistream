import 'package:flutter/material.dart';

import '../../core/settings/settings_scope.dart';
import '../../shared/utils/theater_session.dart';
import 'widgets/custom_magnet_modal.dart';

/// Opens [CustomMagnetModal] to collect a magnet link from the user, then
/// streams it via [runTheaterSession] with no `Anime`/episode context —
/// see that modal's own doc comment for why AniList progress tracking
/// never arms for a stream started this way.
Future<void> launchCustomMagnetStream(BuildContext context) async {
  final bool uiPerformanceMode = SettingsScope.of(
    context,
    listen: false,
  ).settings.uiPerformanceMode;

  final magnetUri = await CustomMagnetModal.show(
    context: context,
    uiPerformanceMode: uiPerformanceMode,
  );

  if (magnetUri != null && context.mounted) {
    await runTheaterSession(
      context: context,
      magnetUri: magnetUri,
      displayTitle: 'Custom Stream',
    );
  }
}
