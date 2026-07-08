import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Tracks whether the app should currently present itself as a TV / D-Pad
/// remote-control interface — visible focus rings, directional focus
/// traversal inside the theater controls, remote-style key shortcuts —
/// versus a normal mouse/touch/keyboard interface (desktop, phone, tablet).
///
/// Two independent signals feed [dpadModeActive]:
///
///  1. [isTvPlatform] — a one-time platform check (Android TV / Google TV
///     "leanback" mode, via a MethodChannel to native Android — see the
///     accompanying MainActivity.kt snippet below). Sticky for the process
///     lifetime: a TV's remote is its only input, so there's nothing to
///     "detect switching away from."
///  2. Live input sniffing — the moment we see a directional/remote key
///     (D-Pad arrows, select, a gamepad face button, the TV "back" key)
///     [dpadModeActive] flips on; the moment we see a pointer-down (mouse
///     click or touch) it flips back off. This is what lets a desktop with a
///     connected gamepad, or a phone paired with a bluetooth remote, get the
///     same treatment as a real TV — and lets a TV box with a mouse attached
///     fall back to pointer-style UI.
///
/// This intentionally does NOT reuse [FocusManager.instance.highlightMode]
/// — that value defaults to "traditional" (rings visible) on desktop
/// platforms from the very first frame, before any real input has happened,
/// which is exactly the "D-Pad bleeding onto PC" bug this class exists to
/// fix. [dpadModeActive] instead starts `false` everywhere except a
/// confirmed TV, and only turns on after D-Pad-shaped input is actually
/// observed.
class InputModeController extends ChangeNotifier {
  InputModeController._();
  static final InputModeController instance = InputModeController._();

  static const MethodChannel _channel = MethodChannel('anistream/device_mode');

  static final Set<LogicalKeyboardKey> _dpadKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.gameButtonB,
    LogicalKeyboardKey.goBack,
  };

  bool _isTvPlatform = false;
  bool _dpadRecentlyUsed = false;
  bool _initialized = false;

  /// True on a confirmed Android TV / Google TV device. Sticky for the
  /// lifetime of the process once detected.
  bool get isTvPlatform => _isTvPlatform;

  /// True whenever the D-Pad/remote-control interaction model should drive
  /// visuals and key handling: either we're on a TV, or the most recent
  /// input event we saw was a directional/remote-style key rather than a
  /// pointer.
  bool get dpadModeActive => _isTvPlatform || _dpadRecentlyUsed;

  /// Call once, early (see [InputModeScope]). Safe to call more than once —
  /// later calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _isTvPlatform = await _detectTv();

    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);

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

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_dpadKeys.contains(event.logicalKey) && !_dpadRecentlyUsed) {
      _dpadRecentlyUsed = true;
      notifyListeners();
    }
    return false; // Passive observer only — never consume the event.
  }

  void _onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent && _dpadRecentlyUsed) {
      _dpadRecentlyUsed = false;
      notifyListeners();
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
