import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_palette.dart';

/// A styled text field for free-form text entry — the settings drawer's
/// server-URL field (`settings_menu.dart`) and `custom_stream`'s
/// pasted-magnet-link field both use this.
///
/// Owns a FocusNode with the same caret-boundary-escape logic
/// search_input.dart uses: arrows move the cursor normally everywhere
/// except the two edges, where they hand off to directional focus
/// traversal instead — so D-Pad/keyboard focus can always escape the
/// field in either direction.
class SettingsTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? label;
  final bool enabled;
  final bool autofocus;
  final TextInputType keyboardType;

  const SettingsTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.enabled = true,
    this.autofocus = false,
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
            // Sits between tileSubtitle (12/w400) and metaLabel
            // (12/w600) — a form field label, not a caption, so it's
            // left as a plain literal rather than either token.
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
          // Covers a D-Pad user navigating onto this field and pressing
          // Select before typing — the TextField itself already grabs
          // focus normally for touch/mouse taps and Tab, this makes
          // Select do the same thing.
          onSelect: _focusNode.requestFocus,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            keyboardType: widget.keyboardType,
            autocorrect: false,
            // Distinct from compactHeading (14/w600), same reasoning as
            // SettingsDropdown's style above.
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
