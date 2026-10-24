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
  // Hover always highlights, but focus only does on a TV platform, so autofocus
  // never draws a ring on PC or mobile (DESIGN.md § 4).
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
    final isTvPlatform = InputModeScope.of(context, listen: false).isTvPlatform;
    callback(_hovered || (_focused && isTvPlatform));
  }

  @override
  Widget build(BuildContext context) {
    final isTvPlatform = InputModeScope.of(context).isTvPlatform;
    final isVisiblyHighlighted = _hovered || (_focused && isTvPlatform);

    final Widget child = FocusableActionDetector(
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