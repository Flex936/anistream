import 'package:flutter/widgets.dart';

/// Owns `AppShell`'s in-memory back/forward history stack. Pure navigation
/// bookkeeping, kept separate from widget state.
class NavigationController extends ChangeNotifier {
  final Widget Function() buildHome;
  NavigationController({required this.buildHome}) {
    _history = [_keyed(buildHome())];
  }

  late final List<Widget> _history;
  final List<Widget> _forwardStack = [];

  // Every pushed widget gets a fresh, incrementing key so Flutter's
  // element reconciliation always treats a navigation as a new subtree,
  // even when the same screen type is shown twice in a row (e.g. tapping
  // the nav bar's Watchlist icon while already on Watchlist). Without
  // this, Flutter's default same-type/same-key update-in-place behavior
  // would reuse the existing Element: the screen's own `initState`-time
  // autofocus wouldn't re-run, and its internal controller state
  // (WatchlistController's pagination, etc.) would go stale instead of
  // resetting.
  int _sequence = 0;

  Widget get current => _history.last;
  bool get canGoBack => _history.length > 1;
  bool get canGoForward => _forwardStack.isNotEmpty;

  Widget _keyed(Widget child) =>
      KeyedSubtree(key: ValueKey(_sequence++), child: child);

  void navigateTo(Widget view) {
    _history.add(_keyed(view));
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
    _history.add(_keyed(buildHome()));
    notifyListeners();
  }
}
