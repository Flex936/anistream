import 'dart:async';

import 'package:flutter/widgets.dart';
import 'input_mode_controller.dart';

/// App-wide access to [InputModeController] without every widget that cares
/// about D-Pad mode reaching for the singleton directly. Mirrors the
/// existing `SettingsScope` pattern — mount once near the root in
/// `app.dart`, then anywhere below it:
/// `InputModeScope.of(context).dpadModeActive`.
class InputModeScope extends StatefulWidget {
  final Widget child;
  const InputModeScope({super.key, required this.child});

  static InputModeController of(BuildContext context, {bool listen = true}) {
    final inherited = listen
        ? context.dependOnInheritedWidgetOfExactType<_InputModeInherited>()
        : context.getInheritedWidgetOfExactType<_InputModeInherited>();
    assert(inherited != null, 'No InputModeScope found in context');
    return inherited!.controller;
  }

  @override
  State<InputModeScope> createState() => _InputModeScopeState();
}

class _InputModeScopeState extends State<InputModeScope> {
  final InputModeController _controller = InputModeController.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.init());
  }

  @override
  Widget build(BuildContext context) {
    return _InputModeInherited(controller: _controller, child: widget.child);
  }
}

class _InputModeInherited extends InheritedNotifier<InputModeController> {
  const _InputModeInherited({
    required InputModeController controller,
    required super.child,
  }) : super(notifier: controller);

  InputModeController get controller => notifier!;
}

/// Convenience accessors for D-Pad/TV-mode-gated behavior. Autofocus and
/// focus-ring visibility both need the same "is this actually a TV/D-Pad
/// session" check (DESIGN.md § 4), so it's centralized here rather than
/// re-reading InputModeScope.of(context) at every call site.
extension DpadModeContext on BuildContext {
  /// Read with `listen: false` — [InputModeController.dpadModeActive] is
  /// a one-time platform check, sticky for the process lifetime (see
  /// that class's own doc comment), so there's nothing to rebuild for
  /// after the first frame and no reason to subscribe every consumer to
  /// it.
  bool get dpadModeActive =>
      InputModeScope.of(this, listen: false).dpadModeActive;

  /// Gates [condition] behind [dpadModeActive] — autofocus should never
  /// silently steal focus on Desktop or Mobile, where there's no remote
  /// driving screen-to-screen navigation. Route every `autofocus:` value
  /// through this instead of passing a raw condition to `DpadFocusable`/
  /// `Focus`/`FocusableActionDetector` directly.
  bool dpadAutofocus(bool condition) => condition && dpadModeActive;
}
