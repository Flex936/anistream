import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// A compact pill-shaped on/off switch, styled to match this app's own
/// chrome rather than Flutter's platform-default `Switch`.
/// `settings_components.dart`'s `SettingRowTile` and
/// `theater_settings.dart`'s Libass toggle row both use this.
class ToggleSwitch extends StatelessWidget {
  final bool value;
  const ToggleSwitch({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: 44,
      height: 24,
      decoration: BoxDecoration(
        color: value
            ? AppPalette.primary
            : AppPalette.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? AppPalette.primary
              : AppPalette.white.withValues(alpha: 0.05),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppPalette.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppPalette.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
