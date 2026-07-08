import 'package:flutter/material.dart';
import '../../core/input/input_mode_scope.dart';

class HoverFocusBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHighlighted) builder;
  final VoidCallback? onTap;
  final bool autofocus;
  final String? tooltip;
  final ValueChanged<bool>? onHoverChanged;

  const HoverFocusBuilder({
    super.key,
    required this.builder,
    this.onTap,
    this.autofocus = false,
    this.tooltip,
    this.onHoverChanged,
  });

  @override
  State<HoverFocusBuilder> createState() => _HoverFocusBuilderState();
}

class _HoverFocusBuilderState extends State<HoverFocusBuilder> {
  // ── Split so the two triggers can be gated independently. Mouse hover is
  // a deliberate signal on every platform and always counts. Keyboard/D-Pad
  // *focus* only visually counts once InputModeScope says we're actually in
  // a TV/D-Pad context — see build() below. This is the one change that
  // stops focus rings from appearing on PC/mobile just because a widget
  // happened to have autofocus, or because Flutter's own default highlight
  // mode starts "traditional" on desktop before any real input happens. ──
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool v) {
    if (v == _hovered) return;
    setState(() => _hovered = v);
    _reportCombined();
  }

  void _setFocused(bool v) {
    if (v == _focused) return;
    setState(() => _focused = v);
    _reportCombined();
  }

  void _reportCombined() {
    final callback = widget.onHoverChanged;
    if (callback == null) return;
    final dpadActive = InputModeScope.of(context, listen: false).dpadModeActive;
    callback(_hovered || (_focused && dpadActive));
  }

  @override
  Widget build(BuildContext context) {
    final dpadActive = InputModeScope.of(context).dpadModeActive;
    final isVisiblyHighlighted = _hovered || (_focused && dpadActive);

    Widget child = FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowHoverHighlight: _setHovered,
      onShowFocusHighlight: _setFocused,
      actions: widget.onTap == null
          ? const {}
          : {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onTap!();
                  return null;
                },
              ),
            },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: widget.builder(context, isVisiblyHighlighted),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(
            message: widget.tooltip!,
            waitDuration: const Duration(milliseconds: 600),
            child: child,
          );
  }
}
