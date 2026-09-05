import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/extensions/build_context_extensions.dart';
import '../../core/theme/app_palette.dart';

/// One selectable option in an [AppSegmentedControl].
@immutable
class AppSegmentedControlItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const AppSegmentedControlItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Shared segmented-control widget — a Material 3 [SegmentedButton] wrapped
/// with a hand-rolled Left/Right D-Pad key handler, the same fix shape as
/// `search_filter_panel.dart`'s slider focus nodes (see that file's own
/// doc comment for the underlying "Material widget swallows arrow keys"
/// problem this pattern works around).
///
/// This is the app's canonical mutually-exclusive option-group control —
/// see DESIGN.md § 1.1 ("every interactive control is a Material widget
/// underneath") for why this replaces CupertinoSlidingSegmentedControl and
/// other hand-rolled tab-row widgets wherever one is needed
/// (`search_filter_panel.dart`'s status filter, `watchlist_screen.dart`'s
/// CURRENT/PLANNING/COMPLETED tabs).
class AppSegmentedControl<T> extends StatefulWidget {
  final List<AppSegmentedControlItem<T>> items;
  final T groupValue;
  final ValueChanged<T> onValueChanged;
  final bool autofocus;

  const AppSegmentedControl({
    super.key,
    required this.items,
    required this.groupValue,
    required this.onValueChanged,
    this.autofocus = false,
  });

  @override
  State<AppSegmentedControl<T>> createState() => _AppSegmentedControlState<T>();
}

class _AppSegmentedControlState<T> extends State<AppSegmentedControl<T>> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'AppSegmentedControl')
      ..onKeyEvent = _handleKey;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // Left/Right always move the selection, even at the first/last item — a
  // fixed enumerated control has no "content" to keep moving through, so
  // there's no case where handing off to spatial traversal on this axis
  // makes sense. Up/Down are always ignored, letting the ambient focus
  // traversal move focus elsewhere.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final currentIndex = widget.items.indexWhere(
      (item) => item.value == widget.groupValue,
    );
    if (currentIndex == -1) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (currentIndex > 0) {
        widget.onValueChanged(widget.items[currentIndex - 1].value);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (currentIndex < widget.items.length - 1) {
        widget.onValueChanged(widget.items[currentIndex + 1].value);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final radii = context.appRadii;
    final typography = context.appTypography;

    return AnimatedBuilder(
      animation: _focusNode,
      builder: (context, child) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radii.small),
          border: Border.all(
            color: _focusNode.hasFocus
                ? AppPalette.primary
                : AppPalette.transparent,
            width: 2,
          ),
        ),
        child: child,
      ),
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        // SegmentedButton renders each segment as its own independently
        // focusable Material button, with no public API to hand it a
        // neutered per-segment FocusNode the way Slider's own `focusNode:`
        // parameter allows (see search_filter_panel.dart's
        // `_minScoreSliderInternalFocusNode` for that alternate fix).
        // descendantsAreFocusable: false is the equivalent guardrail here
        // — every segment stays tappable by mouse/touch, but this outer
        // node is guaranteed to be the only one keyboard/D-Pad focus can
        // ever land on, so the focus ring and _handleKey above both stay
        // anchored to the same node.
        descendantsAreFocusable: false,
        child: SegmentedButton<T>(
          segments: [
            for (final item in widget.items)
              ButtonSegment<T>(
                value: item.value,
                label: Text(item.label),
                icon: item.icon != null ? Icon(item.icon) : null,
              ),
          ],
          selected: {widget.groupValue},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              widget.onValueChanged(selection.first),
          style: SegmentedButton.styleFrom(
            backgroundColor: AppPalette.surface,
            foregroundColor: AppPalette.textMuted,
            selectedBackgroundColor: AppPalette.primary,
            selectedForegroundColor: AppPalette.white,
            side: const BorderSide(color: AppPalette.border),
            textStyle: typography.cardTitleCompact,
            visualDensity: const VisualDensity(vertical: 0.5),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radii.small),
            ),
          ),
        ),
      ),
    );
  }
}
