import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tracks whether the app should currently present itself as a TV / D-Pad
/// remote-control interface — visible focus rings, directional focus
/// traversal inside the theater controls, remote-style key shortcuts —
/// versus a normal mouse/touch/keyboard interface (desktop, phone, tablet).
///
/// [dpadModeActive] is driven by exactly one signal: [isTvPlatform], a
/// one-time platform check (Android TV / Google TV "leanback" mode, via a
/// MethodChannel to native Android — see the accompanying MainActivity.kt
/// snippet below). Sticky for the process lifetime: a TV's remote is its
/// only input, so there's nothing to "detect switching away from."
///
/// Desktop, Android phone, and iOS never enter D-Pad mode, regardless of
/// connected keyboards, gamepads, or Bluetooth remotes — a directional key
/// or gamepad button is ordinary keyboard/pointer input on those
/// platforms, not a TV navigation signal, and is never treated as one.
///
/// This intentionally does NOT reuse [FocusManager.instance.highlightMode]
/// — that value defaults to "traditional" (rings visible) on desktop
/// platforms from the very first frame, before any real input has
/// happened, which is exactly the "D-Pad bleeding onto PC" bug this class
/// exists to fix. [dpadModeActive] is `true` if and only if the app is
/// running on a confirmed TV.
class InputModeController extends ChangeNotifier {
  InputModeController._();
  static final InputModeController instance = InputModeController._();

  static const MethodChannel _channel = MethodChannel('anistream/device_mode');

  bool _isTvPlatform = false;
  bool _initialized = false;

  /// True on a confirmed Android TV / Google TV device. Sticky for the
  /// lifetime of the process once detected.
  bool get isTvPlatform => _isTvPlatform;

  /// True whenever the D-Pad/remote-control interaction model should drive
  /// visuals and key handling. Equivalent to [isTvPlatform] — see the
  /// class doc comment for why no other platform ever sets this.
  bool get dpadModeActive => _isTvPlatform;

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
      // Native side isn't wired up on this build — fail safe to "not a TV"
      // rather than forcing D-Pad UI on every Android device just because
      // the channel is missing.
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
