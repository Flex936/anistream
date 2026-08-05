import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';

/// Tries each mirror URL in order until one responds with 200. Generic
/// over any multi-mirror fetch — the fallback logic itself has nothing to
/// do with Nyaa RSS specifically.
class TorrentMirrorFetcher {
  final http.Client _client;
  TorrentMirrorFetcher(this._client);

  Future<http.Response> fetch({
    required List<String> mirrors,
    required Uri Function(String baseUrl) pathBuilder,
    // A mirror is either up (responds in well under a second) or fully
    // dead/DNS-blocked (times out completely regardless of how long we
    // wait) — there's no real middle ground where a slow-but-alive mirror
    // needs longer to answer. 7s keeps comfortable headroom over a slow
    // connection while keeping the worst-case dead-mirror penalty low,
    // since this sits directly on the click → magnet-link critical path.
    Duration timeout = const Duration(seconds: 7),
  }) async {
    Exception? lastException;

    for (final baseUrl in mirrors) {
      final uri = pathBuilder(baseUrl);
      try {
        final res = await _client.get(uri).timeout(timeout);
        if (res.statusCode == 200) return res;
        lastException = Exception('HTTP ${res.statusCode}');
        AppLogger.w(
          'TorrentMirrorFetcher',
          'Mirror $baseUrl failed with HTTP ${res.statusCode}, trying next mirror',
        );
      } on SocketException {
        lastException = Exception('DNS/Network Block');
        AppLogger.w(
          'TorrentMirrorFetcher',
          'Mirror $baseUrl is blocked or unreachable. Trying next...',
        );
      } on TimeoutException {
        lastException = Exception('Connection Timeout');
        AppLogger.w(
          'TorrentMirrorFetcher',
          'Mirror $baseUrl timed out. Trying next...',
        );
      } catch (e) {
        lastException = Exception(e.toString());
        AppLogger.w('TorrentMirrorFetcher', 'Mirror $baseUrl failed: $e');
      }
    }

    throw Exception(
      'All mirrors failed to respond. Last error: ${lastException?.toString()}',
    );
  }
}
