// lib/services/anilist_auth_service.dart
//
// AniList OAuth 2.0 — implicit grant flow, ported from auth.go.
//
// Flow (identical to the Go implementation):
//   1. Bind a local HTTP server on :3456.
//   2. Open the system browser to the AniList authorisation URL.
//      No redirect_uri in the URL — AniList uses the one registered in the
//      developer portal (http://localhost:3456/callback).
//   3. Serve GET /callback → HTML page whose JS reads window.location.hash
//      and POSTs the raw fragment string to /store.
//   4. POST /store → parse the URL-encoded fragment with Uri.splitQueryString,
//      extract access_token, shut down the server, persist and return.
//
// ── One-time setup ──────────────────────────────────────────────────────────
//   1. Go to https://anilist.co/settings/developer → "Create new client".
//   2. Set "Redirect URL" to exactly:  http://localhost:3456/callback
//   3. Copy the numeric Client ID into [_clientId] below.
//   4. Leave Client Secret blank — the implicit grant does not use it.
//
// Required pubspec dependencies:
//   url_launcher:       ^6.3.0
//   shared_preferences: ^2.3.0   (already required by SettingsService)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AnilistAuthService {
  // ── ↓ Paste your AniList client ID here ─────────────────────────────────
  static const int _clientId = 43011; // e.g. 12345

  // Must match the redirect URL registered in the AniList developer portal.
  static const int _port = 3456;
  static const String _callbackPath = '/callback';
  static const String _storePath = '/store'; // mirrors /store in auth.go
  static const String _prefKey = 'anilist_access_token';

  // ════════════════════════════════════════════════════════════════════════
  //  Token persistence
  // ════════════════════════════════════════════════════════════════════════

  /// Returns the stored Bearer token, or null when logged out.
  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  /// Removes the stored token (logout). Mirrors [Logout] in auth.go.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  OAuth flow  (port of LoginWithAniList in auth.go)
  // ════════════════════════════════════════════════════════════════════════

  /// Returns the access token on success, null on cancel / timeout.
  /// Throws if port [_port] is already in use.
  Future<String?> login() async {
    // ── 1. Bind local server ────────────────────────────────────────────────
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    } on SocketException {
      throw Exception(
        'Cannot start auth server: port $_port is already in use.\n'
        'Close other AniStream windows and try again.',
      );
    }

    // ── 2. Open browser ────────────────────────────────────────────────────
    // No redirect_uri — AniList uses the pre-registered one.
    // Mirrors: fmt.Sprintf(".../authorize?client_id=%s&response_type=token", clientID)
    final authUri = Uri.parse(
      'https://anilist.co/api/v2/oauth/authorize'
      '?client_id=$_clientId'
      '&response_type=token',
    );
    await launchUrl(authUri, mode: LaunchMode.externalApplication);

    // ── 3. Handle callback + store ──────────────────────────────────────────
    final tokenCompleter = Completer<String?>();

    server.listen((HttpRequest req) async {
      switch (req.uri.path) {
        // GET /callback — serve the HTML bridge page.
        // Mirrors the mux.HandleFunc("/callback", …) handler in auth.go.
        case _callbackPath when req.method == 'GET':
          req.response
            ..statusCode = 200
            ..headers.set('Content-Type', 'text/html; charset=utf-8')
            ..write(_callbackHtml);
          await req.response.close();

        // POST /store — JS has POSTed the raw URL hash fragment, e.g.:
        //   "access_token=TOKEN&token_type=Bearer&expires_in=31536000"
        // Parse with Uri.splitQueryString (≡ Go's url.ParseQuery).
        // Mirrors the mux.HandleFunc("/store", …) handler in auth.go.
        case _storePath when req.method == 'POST':
          final body = (await utf8.decodeStream(req)).trim();
          final params = Uri.splitQueryString(body); // same as url.ParseQuery
          final token = params['access_token'];

          req.response
            ..statusCode = 200
            ..write('OK');
          await req.response.close();

          if (!tokenCompleter.isCompleted) {
            tokenCompleter.complete(token?.isNotEmpty == true ? token : null);
          }

        default:
          req.response.statusCode = 404;
          await req.response.close();
      }
    });

    // ── 4. Await token with a 5-minute safety timeout ──────────────────────
    String? token;
    try {
      token = await tokenCompleter.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => null,
      );
    } finally {
      await server.close(force: true);
    }

    // ── 5. Persist ──────────────────────────────────────────────────────────
    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, token);
    }
    return token;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  Callback HTML  (mirrors the inline HTML string in auth.go)
  // ════════════════════════════════════════════════════════════════════════

  /// Served at GET /callback.
  ///
  /// The JS reads [window.location.hash] (e.g. #access_token=TOKEN&…),
  /// strips the leading '#', and POSTs the raw fragment string to /store —
  /// exactly as the Go version does.  The server never sees URL fragments
  /// directly; this JS bridge is the only way to capture them.
  static const String _callbackHtml = r'''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>AniStream — Login</title>
  <style>
    body {
      font-family: sans-serif; text-align: center;
      margin-top: 50px; background: #0a0a0c; color: #f1f5f9;
    }
  </style>
</head>
<body>
  <h2>Authenticating&hellip;</h2>
  <script>
    var hash = window.location.hash.substring(1);
    fetch('/store', { method: 'POST', body: hash })
      .then(function () {
        document.body.innerHTML =
          "<h2 style='color:#6366f1'>Success!</h2>" +
          "<p>You can close this window and return to AniStream.</p>";
      })
      .catch(function () {
        document.body.innerHTML =
          "<h2 style='color:#f87171'>Authentication Failed</h2>" +
          "<p>Please close this window and try again.</p>";
      });
  </script>
</body>
</html>
''';
}
