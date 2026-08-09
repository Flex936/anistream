import 'dart:ui';

import 'package:flutter/material.dart';

/// Design-system translucent-material tiers for `FrostedContainer`'s
/// `sigma` parameter. Three named tiers, following the "bigger surface ->
/// higher blur" pattern DESIGN.md § 1.4 describes.
///
/// Accessed via `context.appMaterials` (see build_context_extensions.dart).
@immutable
class AppMaterials extends ThemeExtension<AppMaterials> {
  /// Small controls — badges, icon buttons, floating pill buttons. Used by
  /// `anime_card.dart`'s `_StatusBadge`, `theater_player.dart`'s
  /// `FrostedIconButton`, `watchlist_cards.dart`'s `WatchlistCard` badge,
  /// `anime_carousel.dart`'s `_NavArrow`, and `hero_banner.dart`'s
  /// `_FloatingNavBar`.
  final double subtle;

  /// Content surfaces — dropdowns, popups, menus, full-screen loading
  /// overlays. Used by `search_input.dart`'s dropdown,
  /// `theater_settings.dart`'s `TheaterSettingsMenu`,
  /// `anime_details_screen.dart`'s loading overlay, and `navbar.dart`'s
  /// scroll-driven animated blur.
  final double standard;

  /// Large panels — side drawers, control bars. Used by
  /// `search_filter_panel.dart`, `theater_controls.dart`'s control bar,
  /// `navbar.dart`'s `_MobileMenu`, `settings_menu.dart`, and
  /// `glass_toast_content.dart`'s toast.
  final double prominent;

  const AppMaterials({
    required this.subtle,
    required this.standard,
    required this.prominent,
  });

  /// 3-tier scale: 10 / 16 / 40. Named `standardTiers` rather than
  /// `standard` (unlike `AppRadii.standard`/`AppTypography.standard`)
  /// because `standard` is already taken by the medium tier field above —
  /// Dart doesn't allow a static and instance member to share a name.
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
