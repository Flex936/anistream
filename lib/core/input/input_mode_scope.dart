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
    _controller.init();
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
