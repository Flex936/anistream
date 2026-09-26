import 'dart:ui';

import 'package:flutter/material.dart';

/// Border-radius tiers (tag / small / large); see DESIGN.md § 1.3.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  /// Small decorative badges and pills.
  final double tag;

  /// List items, cards, carousel tiles, and grid cards.
  final double small;

  /// Modals, bottom sheets, and side panels.
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