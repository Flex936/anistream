import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../logging/app_logger.dart';

/// Which site a deep-linked id came from — see [DeepLinkServer]'s class
/// doc comment for the full flow.
enum DeepLinkSource { anilist, mal }

/// One resolved `/open` request — a bare (site, numeric id) pair. Carries
/// no anime metadata of its own; the browser extension that sent it has
/// none to give (see [DeepLinkServer]).
@immutable
class DeepLinkRequest {
  final DeepLinkSource source;
  final int externalId;

  const DeepLinkRequest({required this.source, required this.externalId});
}

/// Local, loopback-only HTTP listener for the AniStream browser extension
/// companion — the "Open in AniStream" button it injects on AniList and
/// MyAnimeList anime pages. Clicking that button never sends anime
/// metadata, only which site the page is on and the numeric id from the
/// URL (`anilist.co/anime/<id>`, `myanimelist.net/anime/<id>`) — the
/// extension has no way to know more than that. Resolving the id into a
/// real `Anime` and opening `AnimeDetailsScreen` is entirely this app's
/// job, done by whichever widget is listening (see `AppShell`).
///
/// A singleton (`.instance`), matching `InputModeController`'s shape —
/// the underlying `HttpServer` needs to bind once, early, from
/// `main.dart`'s `_bootstrap()`, well before any widget exists to own it.
///
/// [port] is fixed at 53211 specifically to match the extension's own
/// `background.js`, which hardcodes the same value with a comment
/// pointing back to this class by name. Keep both in sync if either ever
/// changes.
///
/// [pending] — rather than a bare broadcast stream — is what lets a
/// request that arrives in the brief window between [start] binding the
/// socket and a listener (`AppShell`) actually mounting still get picked
/// up: a listener checks [pending] directly once on mount, instead of
/// only reacting to a [notifyListeners] call it might have missed.
class DeepLinkServer extends ChangeNotifier {
  DeepLinkServer._();
  static final DeepLinkServer instance = DeepLinkServer._();

  static const int port = 53211;

  HttpServer? _server;

  // Captured rather than left as a bare expression statement so
  // cancel_subscriptions is satisfied — see stop()'s doc comment for why
  // it's never called by default.
  StreamSubscription<HttpRequest>? _subscription;

  DeepLinkRequest? _pending;
  DeepLinkRequest? get pending => _pending;

  /// Binds the listener. Safe to call more than once — a second call
  /// no-ops rather than rebinding. Desktop-only by convention (see
  /// `main.dart`); nothing here enforces that itself.
  Future<void> start() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } catch (e) {
      // Most likely another AniStream instance already owns this port —
      // this instance simply never receives deep links rather than
      // crashing on boot over it.
      AppLogger.w('DeepLinkServer', 'Could not bind port $port: $e');
      return;
    }

    AppLogger.i('DeepLinkServer', 'Listening on http://127.0.0.1:$port');
    _subscription = _server!.listen(
      _handleRequest,
      onError: (Object e) => AppLogger.w('DeepLinkServer', 'Server error: $e'),
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    if (request.method != 'GET' || request.uri.path != '/open') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final source = _parseSource(request.uri.queryParameters['source']);
    final externalId = int.tryParse(request.uri.queryParameters['id'] ?? '');

    if (source == null || externalId == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': false, 'error': 'invalid source or id'}));
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'ok': true}));
    await request.response.close();

    AppLogger.i(
      'DeepLinkServer',
      'Open request: source=${source.name} id=$externalId',
    );

    unawaited(_bringWindowToFront());

    _pending = DeepLinkRequest(source: source, externalId: externalId);
    notifyListeners();
  }

  DeepLinkSource? _parseSource(String? raw) => switch (raw) {
    'anilist' => DeepLinkSource.anilist,
    'mal' => DeepLinkSource.mal,
    _ => null,
  };

  // Best-effort — a request from the extension is exactly the moment the
  // user wants the app in front of them, but a focus failure here isn't
  // worth doing anything more about than logging it; the deep link
  // itself still resolves and navigates regardless.
  Future<void> _bringWindowToFront() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      AppLogger.w('DeepLinkServer', 'Failed to focus window: $e');
    }
  }

  /// Clears [pending] once a listener has read and started acting on it.
  /// Called by `AppShell` immediately after picking a request up, so a
  /// later rebuild or a second listener never replays the same request.
  void consume() => _pending = null;

  /// Explicit teardown — not currently called from anywhere (there's no
  /// "app is exiting" hook that needs it, and the OS reclaims the socket
  /// on process exit regardless), but kept available for tests or a
  /// future explicit disable-this-feature setting. Mirrors
  /// `TorrentParserWorker.dispose()`'s identical rationale.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
  }
}