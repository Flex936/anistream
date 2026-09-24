import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/toggle_switch.dart';

class SettingsSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final bool showDividerAbove;

  const SettingsSection({
    super.key,
    required this.label,
    required this.children,
    this.showDividerAbove = false,
  });

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDividerAbove) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: AppPalette.white.withValues(alpha: 0.1)),
          ),
          const SizedBox(height: 24),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            label.toUpperCase(),
            style: typography.sectionEyebrow.copyWith(
              color: AppPalette.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }
}

class SettingRowTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool autofocus;

  const SettingRowTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;

    return DpadFocusable(
      autofocus: autofocus,
      onSelect: () => onChanged(!value),
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: state.focused
              ? AppPalette.white.withValues(alpha: 0.06)
              : AppPalette.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: typography.compactHeading.copyWith(
                      color: state.focused
                          ? AppPalette.white
                          : AppPalette.textMain,
                    ),
                    child: Text(title),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: typography.tileSubtitle.copyWith(
                      color: AppPalette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ToggleSwitch(value: value),
          ],
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

class SettingsDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  final List<DropdownMenuItem<String>> items;

  const SettingsDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    // excludeChildFocus: false — DropdownButton needs to keep handling
    // its own taps/opens internally (it manages its own overlay menu),
    // so it can't be fully subsumed by DpadFocusable's own onSelect
    // model the way a plain icon button can. DpadFocusable here exists
    // purely to make this reachable via D-Pad directional navigation and
    // to drive the border/background from state.focused; the actual
    // dropdown interaction stays with DropdownButton itself. The
    // DropdownButton doesn't visually depend on state.focused, so it's
    // passed through `child` rather than rebuilt inside `builder`.
    return DpadFocusable(
      excludeChildFocus: false,
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: state.focused
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: state.focused
                ? AppPalette.white.withValues(alpha: 0.2)
                : AppPalette.white.withValues(alpha: 0.1),
          ),
        ),
        child: child,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: AppPalette.surface,
          icon: const Icon(
            Icons.expand_more_rounded,
            color: AppPalette.textMuted,
          ),
          isExpanded: true,
          // Distinct from compactHeading (14/w600) — a dropdown's own
          // selected-value text is deliberately a step lighter than a
          // section heading.
          style: const TextStyle(
            color: AppPalette.textMain,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class SettingsCloseButton extends StatelessWidget {
  final VoidCallback onPressed;
  const SettingsCloseButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      onSelect: onPressed,
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: state.focused
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.close_rounded,
          size: 22,
          color: state.focused ? AppPalette.white : AppPalette.textMuted,
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
