import 'dart:async';
import 'dart:io' show Platform;

import 'package:media_kit/media_kit.dart';

import '../../../core/settings/settings_service.dart';

/// Shared mpv property configuration for the theater window — respects the
/// user's saved hardware-decoding preference per platform, and scales
/// demuxer buffer size and software-decode thread count down under
/// `uiPerformanceMode` (see DESIGN.md § 2).
abstract final class PlayerConfigurator {
  /// Returns `Future<void>` and is awaited by callers: `NativePlayer.
  /// setProperty` itself returns `Future\<void>\`, and each property set
  /// below needs to complete before the next one is meaningful, so the
  /// whole sequence is awaited rather than fired fire-and-forget.
  static Future<void> configureForTheater(
    Player player,
    AppSettings settings,
  ) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    final hwdec = settings.hardwareDecoding;
    if (hwdec == 'auto') {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await platform.setProperty('hwdec', 'auto-safe');
      } else if (Platform.isAndroid) {
        await platform.setProperty('hwdec', settings.androidHwDec);
      } else if (Platform.isIOS) {
        await platform.setProperty('hwdec', 'videotoolbox');
      }
    } else if (hwdec != 'none') {
      await platform.setProperty('hwdec', hwdec);
    }
    await _applyStreamingTuning(platform, settings.uiPerformanceMode);
  }

  static Future<void> _applyStreamingTuning(
    NativePlayer platform,
    bool uiPerformanceMode,
  ) async {
    await platform.setProperty('cache', 'yes');

    // Demuxer cache/readahead is smaller under uiPerformanceMode — the
    // flag this app already uses to mean "treat this device as
    // memory/GPU-constrained" (most commonly an Android TV box; see
    // DESIGN.md § 2). A smaller window still keeps mpv comfortably ahead
    // of a sequentially-downloaded torrent stream, at a fraction of the
    // resident memory cost of the value used elsewhere. Matches the
    // bufferSize theater_screen.dart passes into PlayerConfiguration at
    // Player construction, so the demuxer cache is never briefly at one
    // size and then a different one moments later.
    await platform.setProperty(
      'demuxer-max-bytes',
      uiPerformanceMode ? '70000000' : '150000000',
    );
    await platform.setProperty(
      'demuxer-readahead-secs',
      uiPerformanceMode ? '45' : '120',
    );

    // Caps software-decode thread count under uiPerformanceMode. Only
    // reachable via mpv's software-decode fallback path — hwdec never
    // touches this property — so this only matters once hardware decode
    // has already failed. A weak TV SoC falling back to software
    // shouldn't also be left to spin up mpv's own default thread count
    // and compete with the UI isolate for CPU.
    if (uiPerformanceMode) {
      await platform.setProperty('vd-lavc-threads', '2');
    }

    // HTTP reconnect tuning.
    //
    // Both streaming paths this app supports (StreamingController's local
    // loopback HTTP server backed by libtorrent_flutter, and
    // RemoteStreamingController's LAN HTTP connection to the Go server —
    // see API.md § 1 and ARCHITECTURE.md § 5) are plain HTTP(S) streams
    // read via mpv's ffmpeg/libavformat-backed network stream
    // implementation. A long pause routinely outlives the underlying TCP
    // connection's keep-alive window — closed by the OS, by the local
    // server idling out a connection with nothing actively reading it, or
    // by an intermediate NAT/router on a LAN path — and mpv's demuxer has
    // no built-in awareness that the socket died out from under it. Left
    // at its defaults, it never proactively reissues the ranged GET, so
    // resuming or scrubbing reads from a connection that's already gone,
    // which is indistinguishable from a permanent freeze to the user.
    //
    // network-timeout bounds how long mpv will block on a stalled read
    // before giving up and (with reconnect enabled below) retrying,
    // rather than mpv's own default of 0 — no timeout at all, i.e. an
    // unbounded wait the app has no way to recover from on its own.
    // stream-lavf-o's reconnect flags are libavformat's standard
    // mitigation for a dropped HTTP connection:
    //   reconnect=1                  — enable automatic reconnection
    //   reconnect_streamed=1         — also allow it for streamed
    //                                   (non-seekable-at-the-source)
    //                                   inputs, which is what both of
    //                                   this app's backends serve
    //   reconnect_on_network_error=1 — trigger on a network-level
    //                                   failure (a reset/dropped socket),
    //                                   not only an HTTP error response
    //   reconnect_delay_max=5        — cap the retry backoff at 5s so a
    //                                   resume/seek recovers promptly
    //                                   instead of sitting through a
    //                                   long exponential backoff
    //
    // This is a targeted mitigation for the specific failure mode
    // PlaybackDiagnostics (playback_diagnostics.dart) is designed to
    // confirm — not a guaranteed fix for every possible cause of a
    // frozen frame. If the diagnostic logs show the freeze reproducing
    // with demuxer-cache-idle/core-idle already "no" (i.e. mpv believes
    // it's still actively reading), the root cause lies elsewhere and
    // this tuning alone won't resolve it — see playback_diagnostics.dart's
    // class doc for what to look for.
    await platform.setProperty('network-timeout', '10');
    await platform.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
    );
  }
}
