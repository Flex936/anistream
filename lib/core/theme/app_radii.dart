import 'dart:ui';

import 'package:flutter/material.dart';

/// Design-system radius tiers. `small`/`large` match DESIGN.md's
/// documented scale exactly ("12px for list items, 24px for
/// modals/bottom sheets"). `tag` is a third tier DESIGN.md doesn't
/// explicitly call out, added for small decorative badges/pills
/// (release-group tags, status badges, "UP NEXT" labels) that the
/// codebase already used fairly consistently (4-8px) but never named —
/// same spirit as DESIGN.md's own "extend the palette logically if new
/// shades are required" clause, applied to radii instead of color.
///
/// Accessed via `context.appRadii` (see build_context_extensions.dart).
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  /// Small decorative badges/pills — release-group tags, status badges,
  /// "UP NEXT" labels, seeder pills.
  final double tag;

  /// List items, cards, carousel tiles, grid cards. Matches DESIGN.md's
  /// documented "12px for list items" exactly.
  final double small;

  /// Modals, bottom sheets, side panels. Matches DESIGN.md's documented
  /// "24px for modals/bottom sheets" exactly.
  final double large;

  const AppRadii({required this.tag, required this.small, required this.large});

  /// 3-tier scale: 6 / 12 / 24.
  static const AppRadii standard = AppRadii(tag: 6, small: 12, large: 24);

  @override
  AppRadii copyWith({double? tag, double? small, double? large}) {
    return AppRadii(
      tag: tag ?? this.tag,
      small: small ?? this.small,
      large: large ?? this.large,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    return AppRadii(
      tag: lerpDouble(tag, other.tag, t) ?? tag,
      small: lerpDouble(small, other.small, t) ?? small,
      large: lerpDouble(large, other.large, t) ?? large,
    );
  }
}
