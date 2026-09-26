import 'package:flutter/material.dart';

import '../theme/app_card_sizes.dart';
import '../theme/app_materials.dart';
import '../theme/app_radii.dart';
import '../theme/app_typography.dart';

/// Shared responsive breakpoints, so no screen hardcodes its own.
abstract final class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1500;
}

extension ResponsiveContext on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  bool get isMobile => _width < Breakpoints.mobile;

  /// Standard horizontal content padding.
  double get screenHPad => isMobile ? 16.0 : 32.0;
}

/// The `!` lookups are safe because `app.dart` always registers all four
/// extensions; a null would mean one was removed, a configuration bug worth
/// crashing on.
extension AppThemeContext on BuildContext {
  AppTypography get appTypography => Theme.of(this).extension<AppTypography>()!;

  AppRadii get appRadii => Theme.of(this).extension<AppRadii>()!;

  AppMaterials get appMaterials => Theme.of(this).extension<AppMaterials>()!;

  AppCardSizes get appCardSizes => Theme.of(this).extension<AppCardSizes>()!;
}