import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AnilistAuthService {
  static const int _clientId = 43011;
  static const int _port = 3456;
  static const String _callbackPath = '/callback';
  static const String _storePath = '/store';
  static const String _prefKey = 'anilist_access_token';

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  Future<String?> login() async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    } on SocketException {
      throw Exception(
        'Cannot start auth server: port $_port is already in use. Close other AniStream windows and try again.',
      );
    }

    final authUri = Uri.parse(
      'https://anilist.co/api/v2/oauth/authorize?client_id=$_clientId&response_type=token',
    );
    await launchUrl(authUri, mode: LaunchMode.externalApplication);

    final tokenCompleter = Completer<String?>();

    server.listen((HttpRequest req) async {
      switch (req.uri.path) {
        case _callbackPath when req.method == 'GET':
          req.response
            ..statusCode = 200
            ..headers.set('Content-Type', 'text/html; charset=utf-8')
            ..write(_callbackHtml);
          await req.response.close();

        case _storePath when req.method == 'POST':
          final body = (await utf8.decodeStream(req)).trim();
          final params = Uri.splitQueryString(body);
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

    String? token;
    try {
      token = await tokenCompleter.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => null,
      );
    } finally {
      await server.close(force: true);
    }

    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, token);
    }
    return token;
  }

  static const String _callbackHtml = r'''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>AniStream — Login</title>
  <style>
    body { font-family: sans-serif; text-align: center; margin-top: 50px; background: #0a0a0c; color: #f1f5f9; }
  </style>
</head>
<body>
  <h2>Authenticating&hellip;</h2>
  <script>
    var hash = window.location.hash.substring(1);
    fetch('/store', { method: 'POST', body: hash })
      .then(function () { document.body.innerHTML = "<h2 style='color:#6366f1'>Success!</h2><p>You can close this window and return to AniStream.</p>"; })
      .catch(function () { document.body.innerHTML = "<h2 style='color:#f87171'>Authentication Failed</h2><p>Please close this window and try again.</p>"; });
  </script>
</body>
</html>
''';
}
