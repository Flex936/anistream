import 'dart:ui';

import 'package:flutter/material.dart';

/// Design-system translucent-material tiers for `FrostedContainer`'s
/// `sigma` parameter. Replaces the arbitrary per-call-site blur values
/// (6/10/12/16/20/30/40/50) that used to be scattered across the codebase
/// with three named tiers, following the same "bigger surface -> higher
/// blur" pattern DESIGN.md § 1.4 describes.
///
/// Accessed via `context.appMaterials` (see build_context_extensions.dart).
@immutable
class AppMaterials extends ThemeExtension<AppMaterials> {
  /// Small controls — badges, icon buttons, floating pill buttons.
  /// Converges `anime_card.dart`'s `_StatusBadge` (was 6),
  /// `theater_player.dart`'s `FrostedIconButton` (was 10, exact match),
  /// `watchlist_cards.dart`'s `WatchlistCard` badge (was 10, exact match),
  /// `anime_carousel.dart`'s `_NavArrow` (was a raw BackdropFilter at 10,
  /// exact match), and `hero_banner.dart`'s `_FloatingNavBar` (was 12).
  final double subtle;

  /// Content surfaces — dropdowns, popups, menus, full-screen loading
  /// overlays. Converges `search_input.dart`'s dropdown (was 16, exact
  /// match), `theater_settings.dart`'s `TheaterSettingsMenu` (was 16,
  /// exact match), `anime_details_screen.dart`'s loading overlay (was 12),
  /// and is the target ceiling for `navbar.dart`'s scroll-driven animated
  /// blur (was a literal 16.0, exact match).
  final double standard;

  /// Large panels — side drawers, control bars. Converges
  /// `search_filter_panel.dart` (was 30), `theater_controls.dart`'s
  /// control bar (was 30), `navbar.dart`'s `_MobileMenu` (was 40, exact
  /// match), `settings_menu.dart` (was 50), and
  /// `glass_toast_content.dart`'s toast (was 30 despite being a small
  /// pill — converged here rather than left as an outlier).
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
