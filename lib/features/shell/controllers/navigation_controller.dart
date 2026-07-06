import 'package:flutter/widgets.dart';

/// Extracted from `_AppShellState`: an in-memory back/forward history
/// stack. Pure navigation bookkeeping — it had no business being widget
/// state.
class NavigationController extends ChangeNotifier {
  final Widget Function() buildHome;
  NavigationController({required this.buildHome}) {
    _history = [buildHome()];
  }

  late final List<Widget> _history;
  final List<Widget> _forwardStack = [];

  Widget get current => _history.last;
  bool get canGoBack => _history.length > 1;
  bool get canGoForward => _forwardStack.isNotEmpty;

  void navigateTo(Widget view) {
    _history.add(view);
    _forwardStack.clear();
    notifyListeners();
  }

  bool goBack() {
    if (!canGoBack) return false;
    _forwardStack.add(_history.removeLast());
    notifyListeners();
    return true;
  }

  bool goForward() {
    if (!canGoForward) return false;
    _history.add(_forwardStack.removeLast());
    notifyListeners();
    return true;
  }

  void goHome() {
    _history.clear();
    _forwardStack.clear();
    _history.add(buildHome());
    notifyListeners();
  }
}
