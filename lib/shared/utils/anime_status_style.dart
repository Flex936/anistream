import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

extension AnimeStatusStyle on String? {
  Color get statusColor => switch (this) {
    'RELEASING' => AppPalette.statusReleasing,
    'FINISHED' => AppPalette.statusFinished,
    'CANCELLED' => AppPalette.statusCancelled,
    'HIATUS' => AppPalette.statusHiatus,
    _ => AppPalette.statusDefault,
  };

  String get statusLabel => (this ?? 'UNKNOWN').replaceAll('_', ' ');
}
