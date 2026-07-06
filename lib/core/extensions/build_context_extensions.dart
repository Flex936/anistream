import 'package:flutter/material.dart';

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
