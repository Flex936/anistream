import 'package:flutter/material.dart';

class HoverFocusBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHighlighted) builder;
  final VoidCallback? onTap;
  final bool autofocus;
  final String? tooltip;
  // ── FIXED: Added callback to support external UI updates on hover ──
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
  bool _highlighted = false;

  void _setHighlighted(bool v) {
    if (v != _highlighted) {
      setState(() => _highlighted = v);
      widget.onHoverChanged?.call(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child = FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowHoverHighlight: _setHighlighted,
      onShowFocusHighlight: _setHighlighted,
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
        child: widget.builder(context, _highlighted),
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
