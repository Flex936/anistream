import 'package:flutter/material.dart';
import 'settings_service.dart';

/// App-wide access to [AppSettings] without every screen re-implementing
/// "load on initState, setState when mounted." Installed once near the
/// root in `app.dart`. Anywhere below it:
/// `SettingsScope.of(context).uiPerformanceMode`.
class SettingsScope extends StatefulWidget {
  final Widget child;
  const SettingsScope({super.key, required this.child});

  static SettingsController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<_SettingsInherited>()
        : context.getInheritedWidgetOfExactType<_SettingsInherited>();
    assert(scope != null, 'No SettingsScope found in context');
    return scope!.controller;
  }

  @override
  State<SettingsScope> createState() => _SettingsScopeState();
}

class _SettingsScopeState extends State<SettingsScope> {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsController()..reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          _SettingsInherited(controller: _controller, child: widget.child),
    );
  }
}

class _SettingsInherited extends InheritedWidget {
  final SettingsController controller;
  const _SettingsInherited({required this.controller, required super.child});

  @override
  bool updateShouldNotify(_SettingsInherited old) =>
      old.controller.settings != controller.settings;
}

/// Holds the current [AppSettings] snapshot; notifies on [reload]/[update].
class SettingsController extends ChangeNotifier {
  final SettingsService _service;
  SettingsController({SettingsService? service})
    : _service = service ?? SettingsService();

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;
  bool get uiPerformanceMode => _settings.uiPerformanceMode;

  Future<void> reload() async {
    _settings = await _service.load();
    notifyListeners();
  }

  Future<void> update(AppSettings newSettings) async {
    await _service.save(newSettings);
    _settings = newSettings;
    notifyListeners();
  }
}
