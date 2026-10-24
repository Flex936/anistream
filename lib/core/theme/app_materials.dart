import 'dart:ui';

import 'package:flutter/material.dart';

/// Blur-sigma tiers for `FrostedContainer` (subtle / standard / prominent); see
/// DESIGN.md § 1.4.
@immutable
class AppMaterials extends ThemeExtension<AppMaterials> {
  /// Small controls: badges, icon buttons, floating pill buttons.
  final double subtle;

  /// Content surfaces: dropdowns, popups, menus, loading overlays.
  final double standard;

  /// Large panels: side drawers, control bars, toasts.
  final double prominent;

  const AppMaterials({
    required this.subtle,
    required this.standard,
    required this.prominent,
  });

  /// Tiers 10 / 16 / 40. Named `standardTiers` because the medium-tier field
  /// already takes `standard`, and Dart forbids a static and an instance member
  /// sharing a name.
  static const AppMaterials standardTiers = AppMaterials(
    subtle: 10,
    standard: 16,
    prominent: 40,
  );

  @override
  AppMaterials copyWith({double? subtle, double? standard, double? prominent}) {
    return AppMaterials(
      subtle: subtle ?? this.subtle,
      standard: standard ?? this.standard,
      prominent: prominent ?? this.prominent,
    );
  }

  @override
  AppMaterials lerp(ThemeExtension<AppMaterials>? other, double t) {
    if (other is! AppMaterials) return this;
    return AppMaterials(
      subtle: lerpDouble(subtle, other.subtle, t) ?? subtle,
      standard: lerpDouble(standard, other.standard, t) ?? standard,
      prominent: lerpDouble(prominent, other.prominent, t) ?? prominent,
    );
  }
}