import 'dart:ui';

import 'package:flutter/material.dart';

/// Card-sizing tokens: the poster aspect ratio (2:3, matching AniList's cover
/// art) and the shelf and grid widths (DESIGN.md § 1.3).
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