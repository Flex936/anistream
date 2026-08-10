import 'package:flutter/material.dart';

import '../theme/app_card_sizes.dart';
import '../theme/app_materials.dart';
import '../theme/app_radii.dart';
import '../theme/app_typography.dart';

/// Shared responsive breakpoints so every screen agrees on what "mobile"
/// means, instead of each file hardcoding its own `< 600` check.
abstract final class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1500;
}

extension ResponsiveContext on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  bool get isMobile => _width < Breakpoints.mobile;

  /// Standard horizontal content padding used across list/grid screens.
  double get screenHPad => isMobile ? 16.0 : 32.0;
}

/// All four extensions are registered on `ThemeData.extensions` in
/// app.dart; the `!` below is safe precisely because they're always
/// registered there — if any lookup ever returns null it means
/// the extension was removed from ThemeData, which is a real configuration
/// bug worth crashing loudly on rather than silently falling back.
extension AppThemeContext on BuildContext {
  /// Named typography tokens, e.g. `context.appTypography.cardTitleCompact`.
  /// Deliberately excludes color — see AppTypography's doc comment.
  AppTypography get appTypography => Theme.of(this).extension<AppTypography>()!;

  /// Named radius tiers, e.g. `context.appRadii.small`. Matches
  /// DESIGN.md's documented tag/small/large scale.
  AppRadii get appRadii => Theme.of(this).extension<AppRadii>()!;

  /// Named translucent-material blur tiers, e.g.
  /// `context.appMaterials.subtle`. Matches DESIGN.md's documented
  /// subtle/standard/prominent scale.
  AppMaterials get appMaterials => Theme.of(this).extension<AppMaterials>()!;

  /// Named card-sizing tokens — poster aspect ratio and shelf/grid width
  /// tiers, e.g. `context.appCardSizes.shelfWidth`. See AppCardSizes's own
  /// doc comment for what each token governs.
  AppCardSizes get appCardSizes => Theme.of(this).extension<AppCardSizes>()!;
}
