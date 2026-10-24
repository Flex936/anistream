import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Reports presses of the mouse back/forward buttons ([kBackMouseButton] and
/// [kForwardMouseButton]) on [child]. It only observes, never consuming the
/// pointer event, so wrapping a whole screen is safe.
class MouseBackForwardListener extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  const MouseBackForwardListener({
    super.key,
    required this.child,
    this.onBack,
    this.onForward,
  });

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons & kBackMouseButton != 0) {
      onBack?.call();
    } else if (event.buttons & kForwardMouseButton != 0) {
      onForward?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}