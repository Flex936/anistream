// lib/data/torrent/services/torrent_parser_worker.dart
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../../../core/logging/app_logger.dart';
import '../models/torrent.dart';
import 'torrent_scoring_engine.dart';

// Regex used only for season-number extraction ahead of scoring. Kept
// local to this file since it's the only step of the parsing pipeline
// that needs it.
final RegExp _seasonExtractRegex = RegExp(
  r'(?:season\s*(\d+)|\bs(\d+)\b)',
  caseSensitive: false,
);

/// Everything one feed-parse request needs, in a single sendable record.
typedef _FeedParseRequest = ({
  String xmlBody,
  String animeTitle,
  int episodeNumber,
  int? totalEpisodes,
  String? format,
  bool batchMode,
});

/// Wire-safe stand-in for [Torrent]. A persistent isolate's
/// [SendPort.send] can only transfer records/lists/maps/primitives
/// (recursively) — not arbitrary class instances. [Torrent]'s fields are
/// already all primitives, so this is a lossless, purely mechanical
/// encode/decode step, not a data model change.
typedef _TorrentWire = ({
  String id,
  String title,
  String releaseGroup,
  String resolution,
  String size,
  int seeders,
  double score,
  bool isBatch,
});

_TorrentWire _encodeTorrent(Torrent t) => (
  id: t.id,
  title: t.title,
  releaseGroup: t.releaseGroup,
  resolution: t.resolution,
  size: t.size,
  seeders: t.seeders,
  score: t.score,
  isBatch: t.isBatch,
);

Torrent _decodeTorrent(_TorrentWire w) => Torrent(
  id: w.id,
  title: w.title,
  releaseGroup: w.releaseGroup,
  resolution: w.resolution,
  size: w.size,
  seeders: w.seeders,
  score: w.score,
  isBatch: w.isBatch,
);

typedef _WorkerRequest = ({int requestId, _FeedParseRequest payload});
typedef _WorkerResponse = ({
  int requestId,
  List<_TorrentWire>? torrents,
  String? error,
});

/// Parses and scores one Nyaa RSS feed body against the given anime/episode
/// context — this is the body of the persistent worker isolate's request
/// handler (see [_workerIsolateMain]), and also the [compute] fallback
/// target used when the worker isn't available.
List<Torrent> _parseAndScoreFeed(_FeedParseRequest req) {
  late final XmlDocument document;
  try {
    document = XmlDocument.parse(req.xmlBody);
  } catch (_) {
    throw Exception('Failed to parse Nyaa RSS feed: invalid XML.');
  }

  final items = document.findAllElements('item');

  final seasonMatch = _seasonExtractRegex.firstMatch(req.animeTitle);
  final targetSeason = seasonMatch != null
      ? (int.tryParse(seasonMatch.group(1) ?? seasonMatch.group(2) ?? '1') ?? 1)
      : 1;

  final animeTitleLower = req.animeTitle.toLowerCase();
  final format = req.format;

  final ctx = (
    animeTitleLower: animeTitleLower,
    hasFinalSeason: animeTitleLower.contains('final season'),
    isMovie: format == 'MOVIE',
    isOvaFormat: format == 'OVA' || format == 'ONA' || format == 'SPECIAL',
    targetSeason: targetSeason,
    episodeNumber: req.episodeNumber,
    totalEpisodes: req.totalEpisodes,
    batchMode: req.batchMode,
  );

  final validTorrents = <Torrent>[];
  for (final item in items) {
    final torrent = TorrentScoringEngine.score(item, ctx);
    if (torrent != null) {
      validTorrents.add(torrent);
    }
  }
  return validTorrents;
}

// Isolate entry point. Must be a top-level (or static) function per
// Isolate.spawn's contract — it cannot close over any TorrentParserWorker
// instance state. Processes requests one at a time from its own inbox;
// see TorrentParserWorker's doc comment for why that's fine here.
void _workerIsolateMain(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  // First message back to main: the port it should send requests to.
  mainSendPort.send(commandPort.sendPort);

  commandPort.listen((dynamic message) {
    final request = message as _WorkerRequest;
    try {
      final result = _parseAndScoreFeed(request.payload);
      mainSendPort.send((
        requestId: request.requestId,
        torrents: result.map(_encodeTorrent).toList(),
        error: null,
      ));
    } catch (e) {
      mainSendPort.send((
        requestId: request.requestId,
        torrents: null,
        error: e.toString(),
      ));
    }
  });
}

/// Owns a single, long-lived isolate that parses+scores Nyaa RSS feeds for
/// the lifetime of the app. Spawn/teardown cost is paid at most once per
/// app run rather than once per search — the parsing/scoring work itself
/// is cheap for a 50-300 item feed, but repeated isolate spawns add up
/// fast, especially with several searches (batch/episode/fallback) firing
/// concurrently, and especially on low-end Android TV hardware.
///
/// Spawned lazily on first use rather than eagerly in `main()` — the
/// entire torrent-search feature (and therefore this worker) is only ever
/// touched after someone opens an anime's episode list, so there's no
/// reason to pay isolate spawn cost during app boot for sessions that
/// never search at all.
///
/// Requests are correlated by an incrementing request id rather than
/// assumed-FIFO pairing, since concurrent fan-out (batch-mode +
/// episode-mode + truncated-title fallback) means multiple
/// [parseAndScore] calls can genuinely be in flight at once. The worker
/// isolate still processes its inbox one message at a time (a single
/// isolate has no internal parallelism), so concurrent requests queue
/// briefly behind each other there — but parsing+scoring one feed is
/// low-single-digit milliseconds of work, so that queueing is negligible
/// next to the network round-trip. A worker *pool* would remove even
/// that queueing, at the cost of real added lifecycle complexity (N
/// isolates, load balancing) for a CPU cost that's already small — not
/// worth it unless on-device profiling says otherwise.
class TorrentParserWorker {
  TorrentParserWorker._();
  static final TorrentParserWorker instance = TorrentParserWorker._();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _responsePort;
  StreamSubscription<dynamic>? _responseSub;

  Completer<void>? _spawning;
  bool _spawnPermanentlyFailed = false;

  int _nextRequestId = 0;
  final Map<int, Completer<List<Torrent>>> _pending = {};

  Future<void> _ensureSpawned() async {
    if (_workerSendPort != null) return;
    if (_spawning != null) return _spawning!.future;
    if (_spawnPermanentlyFailed) return;

    final completer = Completer<void>();
    _spawning = completer;

    try {
      final responsePort = ReceivePort();
      _responsePort = responsePort;
      _responseSub = responsePort.listen(_handleMessage);

      _isolate = await Isolate.spawn(
        _workerIsolateMain,
        responsePort.sendPort,
        onError: responsePort.sendPort,
        onExit: responsePort.sendPort,
        debugName: 'TorrentParserWorker',
      );

      // _handleMessage completes `completer` once the worker's bootstrap
      // SendPort arrives (see the SendPort branch below).
      await completer.future.timeout(const Duration(seconds: 10));
    } catch (e, st) {
      AppLogger.e(
        'TorrentParserWorker',
        'Failed to spawn worker isolate — falling back to compute() for this session',
        e,
        st,
      );
      _spawnPermanentlyFailed = true;
      _teardown();
    } finally {
      // Whether spawning succeeded, failed, or timed out, this unblocks
      // anyone else who was awaiting this same completer via the
      // `_spawning != null` branch above — a second concurrent caller
      // (plausible under concurrent fan-out, e.g. batch-mode and
      // episode-mode both hitting this on the very first search of a
      // session) would otherwise hang: the `.timeout()` above only fails
      // the locally awaited future, it doesn't resolve the shared
      // `completer` itself. Callers only use this signal to mean "the
      // attempt is over, go check `_workerSendPort`" — not "it
      // succeeded" — so completing without an error is correct even on
      // the failure path.
      if (!completer.isCompleted) completer.complete();
      _spawning = null;
    }
  }

  void _handleMessage(dynamic message) {
    // 1. Bootstrap handshake: worker's own SendPort for receiving requests.
    if (message is SendPort) {
      _workerSendPort = message;
      _spawning?.complete();
      return;
    }

    // 2. Clean exit signal (Isolate's onExit sends `null`).
    if (message == null) {
      AppLogger.w('TorrentParserWorker', 'Worker isolate exited');
      _failAllPending('Worker isolate exited unexpectedly');
      _teardown();
      return;
    }

    // 3. Uncaught error surfaced via onError: [errorString, stackTraceString].
    // `List` (no type argument) is a raw type under strict-raw-types;
    // `List<dynamic>` is the honest spelling of "a list of whatever
    // Isolate.onError happened to send." Its `.first` is `dynamic`, so
    // it's cast to `Object?` before `.toString()` is called — strict-casts
    // disallows the implicit dynamic→Object downcast.
    if (message is List<dynamic>) {
      final reason = message.isNotEmpty
          ? (message.first as Object?)?.toString() ?? 'Unknown error'
          : 'Unknown error';
      AppLogger.e('TorrentParserWorker', 'Worker isolate crashed: $reason');
      _failAllPending('Worker isolate crashed: $reason');
      _teardown();
      return;
    }

    // 4. Normal response.
    final response = message as _WorkerResponse;
    final completer = _pending.remove(response.requestId);
    if (completer == null) return; // Stale — nothing waiting on this anymore.

    if (response.error != null) {
      completer.completeError(Exception(response.error));
    } else {
      completer.complete(response.torrents!.map(_decodeTorrent).toList());
    }
  }

  void _failAllPending(String reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(Exception(reason));
    }
    _pending.clear();
  }

  void _teardown() {
    // Cancelled directly off the field (rather than via an intermediate
    // local copy) so the analyzer's cancel_subscriptions check traces the
    // .cancel() call back to this field unambiguously. Still wrapped in
    // unawaited(): StreamSubscription.cancel() returns Future<void>, and
    // _teardown() is called from several synchronous contexts (including
    // inside catch/finally blocks above), so it can't become async
    // without cascading that through every caller.
    unawaited(_responseSub?.cancel() ?? Future<void>.value());
    _responseSub = null;
    _responsePort?.close();
    _responsePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
  }

  /// Parses and scores one Nyaa RSS feed against the given anime/episode
  /// context. Returns the scored [Torrent] list, or throws if the feed
  /// body wasn't valid XML.
  Future<List<Torrent>> parseAndScore({
    required String xmlBody,
    required String animeTitle,
    required int episodeNumber,
    int? totalEpisodes,
    String? format,
    required bool batchMode,
  }) async {
    final payload = (
      xmlBody: xmlBody,
      animeTitle: animeTitle,
      episodeNumber: episodeNumber,
      totalEpisodes: totalEpisodes,
      format: format,
      batchMode: batchMode,
    );

    if (!_spawnPermanentlyFailed) {
      await _ensureSpawned();
    }

    final sendPort = _workerSendPort;
    if (sendPort == null) {
      // Safety net: the worker isolate couldn't be spawned (or died and
      // a respawn attempt also failed). Falls back to a one-shot
      // compute() call rather than letting every torrent search in the
      // app start failing — the feature keeps working, just without the
      // persistent worker's spawn-cost savings for this request.
      AppLogger.w(
        'TorrentParserWorker',
        'Worker unavailable — falling back to compute() for this request',
      );
      return compute(_parseAndScoreFeed, payload);
    }

    final id = _nextRequestId++;
    final completer = Completer<List<Torrent>>();
    _pending[id] = completer;
    sendPort.send((requestId: id, payload: payload));
    return completer.future;
  }

  /// Explicit app-lifetime teardown. Not currently called from anywhere —
  /// there's no "app is exiting" hook in this codebase today, and the
  /// OS/engine reclaims the isolate automatically on process exit
  /// regardless — but kept available for tests or a future explicit
  /// shutdown path.
  void dispose() => _teardown();
}
