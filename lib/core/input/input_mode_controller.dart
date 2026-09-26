import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tracks whether the app presents as a TV / D-Pad interface (focus rings,
/// directional traversal, remote shortcuts) or an ordinary mouse/touch/keyboard
/// one; a connected keyboard, gamepad, or Bluetooth remote on desktop, phone,
/// or iOS never sets it. [isTvPlatform] is a one-time, sticky check for Android
/// TV / Google TV leanback mode (ARCHITECTURE.md § 4) — deliberately not
/// [FocusManager.instance.highlightMode] (DESIGN.md § 4).
class InputModeController extends ChangeNotifier {
  InputModeController._();
  static final InputModeController instance = InputModeController._();

  static const MethodChannel _channel = MethodChannel('anistream/device_mode');

  bool _isTvPlatform = false;
  bool _initialized = false;

  /// True on a confirmed Android TV / Google TV device. Sticky for the
  /// lifetime of the process once detected.
  bool get isTvPlatform => _isTvPlatform;

  /// Call once, early (see [InputModeScope]). Safe to call more than once —
  /// later calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _isTvPlatform = await _detectTv();
    if (_isTvPlatform) notifyListeners();
  }

  Future<bool> _detectTv() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isTelevision');
      return result ?? false;
    } on MissingPluginException {
      // Native side not wired up on this build — fails safe to "not a TV"
      // rather than forcing D-Pad UI everywhere.
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Test hook — lets a widget test force TV mode without a real platform
  /// channel.
  @visibleForTesting
  void debugSetTvPlatform(bool value) {
    _isTvPlatform = value;
    notifyListeners();
  }
}