import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dpad/dpad.dart';
import '../../../core/theme/app_palette.dart';

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
                    style: TextStyle(
                      color: state.focused
                          ? AppPalette.white
                          : AppPalette.textMain,
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
    // ── excludeChildFocus: false — DropdownButton needs to keep handling
    // its own taps/opens internally (it manages its own overlay menu),
    // so it can't be fully subsumed by DpadFocusable's own onSelect
    // model the way a plain icon button can. DpadFocusable here exists
    // purely to make this reachable via D-Pad directional navigation and
    // to drive the border/background from state.focused; the actual
    // dropdown interaction stays exactly as it was. The DropdownButton
    // itself doesn't visually depend on state.focused, so it's passed
    // through `child` rather than rebuilt inside `builder`. ──
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

/// A styled text field for settings values such as the server URL.
///
/// Rebuilt as a StatefulWidget so it can own a FocusNode with the same
/// caret-boundary-escape logic search_input.dart already proved out —
/// arrows move the cursor normally everywhere except the two edges, where
/// they hand off to directional focus traversal instead. This field
/// previously had no such logic at all, which is the whole reason it
/// trapped focus permanently: arrows only ever moved the cursor (or did
/// nothing), with no escape hatch in either direction.
class SettingsTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? label;
  final bool enabled;
  final TextInputType keyboardType;

  const SettingsTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.enabled = true,
    this.keyboardType = TextInputType.url,
  });

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'SettingsTextField');

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        node.focusInDirection(TraversalDirection.up);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        node.focusInDirection(TraversalDirection.down);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        final offset = widget.controller.selection.baseOffset;
        if (offset == widget.controller.text.length || offset == -1) {
          node.focusInDirection(TraversalDirection.right);
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        final offset = widget.controller.selection.baseOffset;
        if (offset <= 0) {
          node.focusInDirection(TraversalDirection.left);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              widget.label!,
              style: const TextStyle(
                color: AppPalette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        DpadFocusable(
          excludeChildFocus: false,
          // ── Requesting focus here covers a D-Pad user navigating onto
          // this field and pressing Select before typing — the TextField
          // itself already grabs focus normally for touch/mouse taps
          // and Tab, this just makes Select do the same thing. ──
          onSelect: () => _focusNode.requestFocus(),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            autocorrect: false,
            style: TextStyle(
              color: widget.enabled
                  ? AppPalette.textMain
                  : AppPalette.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(
                color: AppPalette.textMuted,
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppPalette.white.withValues(
                alpha: widget.enabled ? 0.06 : 0.02,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppPalette.white.withValues(alpha: 0.1),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppPalette.white.withValues(alpha: 0.1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppPalette.primary,
                  width: 1.5,
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppPalette.white.withValues(alpha: 0.05),
                ),
              ),
            ),
          ),
        ),
      ],
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
