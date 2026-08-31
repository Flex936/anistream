import 'package:flutter/foundation.dart';

import '../../../data/anilist/anilist_auth_service.dart';

/// Feature-local wrapper around [AnilistAuthService] that turns its plain
/// `Future<String?>` login contract into an observable in-flight state.
/// `AppShell` listens to this via `addListener` (the same shape
/// `NavigationController` already uses), rebuilding the navbar's login
/// button to show a spinner while [isInProgress] is true, and routing a
/// tap while it's true into [cancel] instead of starting a second
/// concurrent attempt.
class AnilistLoginController extends ChangeNotifier {
  final AnilistAuthService _authService;

  AnilistLoginController({AnilistAuthService? authService})
    : _authService = authService ?? AnilistAuthService();

  bool _isInProgress = false;
  bool get isInProgress => _isInProgress;

  Future<String?> getStoredToken() => _authService.getStoredToken();

  Future<void> logout() => _authService.logout();

  /// Starts a login attempt. [AnilistAuthService.login] already cancels
  /// any stale attempt of its own before starting a new one, so this
  /// never needs to guard against being called while [isInProgress] is
  /// already true — it only reflects that in-flight state for the UI.
  Future<String?> login() async {
    _isInProgress = true;
    notifyListeners();
    try {
      return await _authService.login();
    } finally {
      _isInProgress = false;
      notifyListeners();
    }
  }

  /// Cancels the in-flight attempt, if any — resolves [login]'s pending
  /// call to `null` immediately instead of waiting out its 5-minute
  /// timeout. No-ops when nothing is in progress.
  void cancel() {
    if (!_isInProgress) return;
    _authService.cancel();
  }

  @override
  void dispose() {
    // Releases the loopback port immediately on teardown rather than
    // leaving a genuinely abandoned attempt to time out on its own well
    // after this controller (and the AppShell that owned it) is gone.
    _authService.cancel();
    super.dispose();
  }
}