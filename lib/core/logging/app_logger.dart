// lib/core/logging/app_logger.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warning, error }

extension on LogLevel {
  String get label => switch (this) {
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO ',
    LogLevel.warning => 'WARN ',
    LogLevel.error => 'ERROR',
  };
}

/// Centralized, module-tagged logger for AniStream.
///
/// Usage anywhere in the app:
/// ```dart
/// AppLogger.i('TorrentScraper', 'Searching nyaa.si for "$query"');
/// AppLogger.e('StreamingController', 'Failed to mount stream', error, stack);
/// ```
///
/// Every call:
///  1. Prints to the console via [debugPrint] (handy in dev).
///  2. Buffers the line and flushes it to a rotating log file on disk, so a
///     *release* build (phone, Android TV, headless server box, etc — where
///     there's no attached console) still leaves a readable trail behind
///     after a crash, force-close, or bug report.
///
/// Call [init] once, before `runApp()`, so boot-time errors are captured
/// too. Call [dispose] from your root widget's `dispose()` as a belt-and-
/// braces flush; automatic hooks (see below) cover the rest.
///
/// ── Why the log file stays current even if the app is killed outright ──
/// There is no 100%-guaranteed "on any exit" hook in Flutter/Dart — a hard
/// `kill -9` or a yanked power cord can't be intercepted by anything. This
/// class instead makes that scenario harmless by:
///   • flushing to disk every 2 seconds on a timer (so you lose at most the
///     last ~2s of logs, not the whole session),
///   • flushing immediately on every ERROR-level log,
///   • flushing + closing on FlutterError / PlatformDispatcher uncaught
///     errors,
///   • flushing + closing on app lifecycle transitions to paused/inactive/
///     detached (covers Android/iOS backgrounding and task-kill),
///   • flushing + closing on SIGINT/SIGTERM on desktop (Ctrl+C, window
///     manager close, `kill <pid>`).
abstract final class AppLogger {
  static IOSink? _sink;
  static File? _logFile;
  static Directory? _logsDir;
  static final List<String> _pending = [];
  static Timer? _flushTimer;
  static bool _initialized = false;
  static bool _disposed = false;
  static LogLevel _minLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;

  /// Keep this many previous session log files around; older ones are
  /// pruned on startup so the log folder doesn't grow forever.
  static const int _maxKeptFiles = 10;

  static bool get isInitialized => _initialized;
  static String? get currentLogFilePath => _logFile?.path;
  static String? get logsDirectoryPath => _logsDir?.path;

  /// Sets up the file sink and wires the global error/exit handlers.
  /// Safe to call once; subsequent calls are no-ops.
  static Future<void> init({LogLevel? minLevel}) async {
    if (_initialized) return;
    _initialized = true;
    if (minLevel != null) _minLevel = minLevel;

    try {
      final supportDir = await getApplicationSupportDirectory();
      _logsDir = Directory(p.join(supportDir.path, 'logs'));
      if (!await _logsDir!.exists()) {
        await _logsDir!.create(recursive: true);
      }

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      _logFile = File(p.join(_logsDir!.path, 'anistream_$stamp.log'));
      _sink = _logFile!.openWrite(mode: FileMode.append);

      await _pruneOldLogs();

      _flushTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _flushToDisk(),
      );

      i('AppLogger', 'Logging initialized -> ${_logFile!.path}');
    } catch (err, st) {
      // No writable directory available (unusual, but possible in some
      // sandboxes) — degrade gracefully to console-only logging.
      debugPrint('[AppLogger] Failed to initialize file logging: $err\n$st');
    }

    _installGlobalHandlers();
  }

  static Future<void> _pruneOldLogs() async {
    final dir = _logsDir;
    if (dir == null) return;
    try {
      final entries = await dir.list().toList();
      final files = entries
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      if (files.length > _maxKeptFiles) {
        for (final f in files.skip(_maxKeptFiles)) {
          try {
            await f.delete();
          } catch (_) {
            // Best-effort housekeeping — ignore failures.
          }
        }
      }
    } catch (_) {
      // Non-fatal.
    }
  }

  static void _installGlobalHandlers() {
    // Uncaught Flutter framework errors (widget build errors, etc).
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      e(
        'FlutterError',
        details.exceptionAsString(),
        details.exception,
        details.stack,
      );
      previousOnError?.call(details);
    };

    // Uncaught errors anywhere else in the Dart runtime (async gaps, etc).
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      e('PlatformDispatcher', 'Uncaught error', error, stack);
      previousPlatformOnError?.call(error, stack);
      return false; // still let the platform's own reporting run too
    };

    // Desktop process signals — Ctrl+C, window-manager kill, `kill <pid>`.
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      _listenToSignal(ProcessSignal.sigint);
      if (!Platform.isWindows) {
        _listenToSignal(ProcessSignal.sigterm);
      }
    }
  }

  static void _listenToSignal(ProcessSignal signal) {
    signal.watch().listen((sig) async {
      w('AppLogger', 'Received $sig - flushing logs and exiting.');
      await dispose();
      exit(0);
    });
  }

  /// Wire this into your root widget:
  /// ```dart
  /// @override
  /// void didChangeAppLifecycleState(AppLifecycleState state) {
  ///   AppLogger.onAppLifecycleStateChanged(state);
  /// }
  /// ```
  /// Covers Android/iOS backgrounding and task-kill, where the process may
  /// be torn down without ever reaching a Dart-level "shutdown" callback.
  static void onAppLifecycleStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      i('AppLogger', 'App lifecycle -> $state, flushing logs.');
      unawaited(_flushToDisk());
    }
  }

  static void d(String tag, String message) =>
      _log(LogLevel.debug, tag, message);
  static void i(String tag, String message) =>
      _log(LogLevel.info, tag, message);
  static void w(String tag, String message, [Object? error, StackTrace? st]) =>
      _log(LogLevel.warning, tag, message, error, st);
  static void e(String tag, String message, [Object? error, StackTrace? st]) =>
      _log(LogLevel.error, tag, message, error, st);

  static void _log(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (_disposed || level.index < _minLevel.index) return;

    final time = DateTime.now().toIso8601String();
    final buffer = StringBuffer('[$time] ${level.label} [$tag] $message');
    if (error != null) buffer.write(' -- $error');
    final line = buffer.toString();

    debugPrint(line);
    _pending.add(line);

    if (stackTrace != null && level == LogLevel.error) {
      debugPrint(stackTrace.toString());
      _pending.add(stackTrace.toString());
    }

    // Errors are rare and important — push to disk immediately instead of
    // waiting for the next periodic flush.
    if (level == LogLevel.error) {
      unawaited(_flushToDisk());
    }
  }

  static Future<void> _flushToDisk() async {
    final sink = _sink;
    if (sink == null || _pending.isEmpty) return;

    final toWrite = List<String>.from(_pending);
    _pending.clear();
    try {
      sink.writeln(toWrite.join('\n'));
      await sink.flush();
    } catch (_) {
      // Disk write failed — put the lines back so the next flush retries.
      _pending.insertAll(0, toWrite);
    }
  }

  /// Flushes any buffered lines and closes the file. Safe to call more than
  /// once. Automatic hooks (signals/lifecycle/uncaught errors) already call
  /// this, but call it explicitly from your root widget's `dispose()` too.
  static Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushToDisk();
    await _sink?.close();
    _sink = null;
  }
}
