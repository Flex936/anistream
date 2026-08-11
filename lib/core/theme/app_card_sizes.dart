import 'dart:ui';

import 'package:flutter/material.dart';

/// Design-system card-sizing tokens: the canonical poster aspect ratio and
/// the fixed/capped widths cards render at across shelves and grids.
///
/// `posterAspectRatio` matches AniList's own `coverImage` art exactly
/// (2:3) — `AnimeCard`, `WatchlistCard`, `ListCard`, and `CalendarCard` all
/// size their poster off this single value instead of each picking a
/// different crop of the same source art.
///
/// `shelfWidth` is the fixed card width used by every horizontal
/// carousel/shelf (`AnimeCarousel`, `ScheduledScreen`'s day shelves) —
/// matching widths there is what makes adjacent shelves feel like one
/// system rather than several.
///
/// `gridMaxWidth`/`heroGridMaxWidth` cap how wide a fluid grid card
/// (`SearchResultsScreen`, `WatchlistScreen`) is allowed to grow on a wide
/// desktop, via `SliverGridDelegateWithMaxCrossAxisExtent` rather than a
/// manual breakpoint-to-column-count table.
///
/// Accessed via `context.appCardSizes` (see build_context_extensions.dart).
@immutable
class AppCardSizes extends ThemeExtension<AppCardSizes> {
  final double posterAspectRatio;
  final double shelfWidth;
  final double gridMaxWidth;
  final double heroGridMaxWidth;

  const AppCardSizes({
    required this.posterAspectRatio,
    required this.shelfWidth,
    required this.gridMaxWidth,
    required this.heroGridMaxWidth,
  });

  static const AppCardSizes standard = AppCardSizes(
    posterAspectRatio: 2 / 3,
    shelfWidth: 170,
    gridMaxWidth: 220,
    heroGridMaxWidth: 340,
  );

  @override
  AppCardSizes copyWith({
    double? posterAspectRatio,
    double? shelfWidth,
    double? gridMaxWidth,
    double? heroGridMaxWidth,
  }) {
    return AppCardSizes(
      posterAspectRatio: posterAspectRatio ?? this.posterAspectRatio,
      shelfWidth: shelfWidth ?? this.shelfWidth,
      gridMaxWidth: gridMaxWidth ?? this.gridMaxWidth,
      heroGridMaxWidth: heroGridMaxWidth ?? this.heroGridMaxWidth,
    );
  }

  @override
  AppCardSizes lerp(ThemeExtension<AppCardSizes>? other, double t) {
    if (other is! AppCardSizes) return this;
    return AppCardSizes(
      posterAspectRatio:
          lerpDouble(posterAspectRatio, other.posterAspectRatio, t) ??
          posterAspectRatio,
      shelfWidth: lerpDouble(shelfWidth, other.shelfWidth, t) ?? shelfWidth,
      gridMaxWidth:
          lerpDouble(gridMaxWidth, other.gridMaxWidth, t) ?? gridMaxWidth,
      heroGridMaxWidth:
          lerpDouble(heroGridMaxWidth, other.heroGridMaxWidth, t) ??
          heroGridMaxWidth,
    );
  }
}
