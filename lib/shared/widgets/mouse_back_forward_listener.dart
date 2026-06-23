// lib/shared/widgets/mouse_back_forward_listener.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Wraps [child] and reports presses of the dedicated back/forward buttons
/// found on most mice — the same buttons browsers use for history
/// navigation. Maps to [kBackMouseButton] / [kForwardMouseButton] in
/// Flutter's pointer event model.
///
/// Purely an observer: it never consumes the pointer event, so it's safe to
/// wrap large areas (even a whole screen) without affecting taps or drags
/// underneath it.
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
