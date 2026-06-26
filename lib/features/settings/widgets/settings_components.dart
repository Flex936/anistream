import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

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
            style: const TextStyle(
              color: AppPalette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
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
    return HoverFocusBuilder(
      autofocus: autofocus,
      onTap: () => onChanged(!value),
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: hovered
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
                    style: TextStyle(
                      color: hovered ? AppPalette.white : AppPalette.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    child: Text(title),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppPalette.textMuted,
                      fontSize: 12,
                      height: 1.4,
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
    return HoverFocusBuilder(
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: hovered
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hovered
                ? AppPalette.white.withValues(alpha: 0.2)
                : AppPalette.white.withValues(alpha: 0.1),
          ),
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
            style: const TextStyle(
              color: AppPalette.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            items: items,
            onChanged: onChanged,
          ),
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
    return HoverFocusBuilder(
      onTap: onPressed,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: hovered
              ? AppPalette.white.withValues(alpha: 0.1)
              : AppPalette.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.close_rounded,
          size: 22,
          color: hovered ? AppPalette.white : AppPalette.textMuted,
        ),
      ),
    );
  }
}
