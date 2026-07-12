// lib/data/torrent/services/torrent_parser_worker.dart
import 'dart:async';
import 'dart:isolate';

import 'package:anistream/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../models/torrent.dart';
import 'torrent_scoring_engine.dart';

// ── Regex used only for season-number extraction ahead of scoring. Kept
// local to this file rather than shared with TorrentScraperService's
// title-cleaning regexes — it's the only one of the four the parsing step
// itself actually needs. ──
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
/// [SendPort.send] — unlike `compute()`'s one-shot [Isolate.exit] result
/// path — cannot transfer arbitrary class instances; only
/// records/lists/maps/primitives (recursively) are guaranteed sendable.
/// [Torrent]'s fields are already all primitives, so this is a lossless,
/// purely mechanical encode/decode step, not a data model change.
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

// ── Same parse-and-score logic that used to run inside compute()'s
// throwaway isolate — unchanged math/logic, just now the body of the
// persistent worker's request handler instead of a one-shot callback. ──
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

// ── Isolate entry point. Must be a top-level (or static) function per
// Isolate.spawn's contract — it cannot close over any TorrentParserWorker
// instance state. Processes requests one at a time from its own inbox;
// see TorrentParserWorker's doc comment for why that's fine here. ──
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
/// the lifetime of the app, replacing the previous per-search `compute()`
/// call — which spawned and tore down a fresh isolate on every single
/// search. Spawn/teardown cost is now paid at most once per app run
/// instead of once per feed. The CPU work itself was already cheap for a
/// 50-300 item feed; it was the repeated spawn overhead that added up,
/// especially once Tier 1 made batch/episode/fallback searches run
/// concurrently, and especially on low-end Android TV hardware.
///
/// Spawned lazily on first use rather than eagerly in `main()` — the
/// entire torrent-search feature (and therefore this worker) is only ever
/// touched after someone opens an anime's episode list, so there's no
/// reason to pay isolate spawn cost during app boot for sessions that
/// never search at all. (Eagerly warming this alongside
/// `MediaKit.ensureInitialized()` in `main.dart` is a trivial follow-up if
/// shaving the very first search of a session ever matters more than boot
/// time.)
///
/// Requests are correlated by an incrementing request id rather than
/// assumed-FIFO pairing — Tier 1's concurrent fan-out (batch-mode +
/// episode-mode + truncated-title fallback) means multiple
/// [parseAndScore] calls can genuinely be in flight at once. The worker
/// isolate still processes its inbox one message at a time (a single
/// isolate has no internal parallelism), so concurrent requests queue
/// briefly behind each other there — but parsing+scoring one feed is
/// low-single-digit milliseconds of work, so that queueing is negligible
/// next to the network round-trip and the spawn cost this class removes.
/// A worker *pool* would remove even that queueing, at the cost of real
/// added lifecycle complexity (N isolates, load balancing) for a CPU cost
/// that's already small — not worth it unless on-device profiling says
/// otherwise.
class TorrentParserWorker {
  TorrentParserWorker._();
  static final TorrentParserWorker instance = TorrentParserWorker._();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _responsePort;
  StreamSubscription? _responseSub;

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
      // Whether spawning succeeded, failed, or timed out, unblock anyone
      // ELSE who was awaiting this SAME completer via the
      // `_spawning != null` branch above. Without this, a second
      // concurrent caller (very plausible under Tier 1's fan-out — e.g.
      // batch-mode and episode-mode both hitting this on the very first
      // search of a session) would hang forever: the `.timeout()` above
      // only fails the LOCAL awaited future, it doesn't resolve the
      // shared `completer` itself. Callers only use this signal to mean
      // "the attempt is over, go check `_workerSendPort`" — not "it
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
    if (message is List) {
      final reason = message.isNotEmpty ? message.first : 'Unknown error';
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
    _responseSub?.cancel();
    _responseSub = null;
    _responsePort?.close();
    _responsePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
  }

  /// Parses and scores one Nyaa RSS feed against the given anime/episode
  /// context. Same contract `compute(_parseAndScoreFeed, ...)` used to
  /// have: returns the scored [Torrent] list, or throws if the feed body
  /// wasn't valid XML.
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
      // ── Safety net: the worker isolate could not be spawned (or died
      // and a respawn attempt also failed). Rather than let every torrent
      // search in the app start failing, fall back to the original
      // one-shot compute() behavior — the feature keeps working, just
      // without Tier 3's spawn-cost savings for this request. ──
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
