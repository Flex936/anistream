// lib/data/torrent/torrent_scraper_service.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../anilist/models/anime.dart';
import 'models/torrent.dart';
import 'models/tsukihime_models.dart';
import 'services/torrent_mirror_fetcher.dart';
import 'services/torrent_parser_worker.dart';
import 'services/tracker_scrape_service.dart';
import 'services/tsukihime_api_service.dart';

abstract final class _QueryRegex {
  static final stripTags = RegExp(
    r'(?:season\s*\d+|\bs\d+\b|part\s*\d+|cour\s*\d+)',
    caseSensitive: false,
  );
  static final punctuation = RegExp(r"[:!?',\-.]");
  static final whitespace = RegExp(r'\s+');
}

/// Shape of the `trySearch` closure defined inside `fetchTorrents`.
typedef _TrySearchFn =
    Future<List<Torrent>> Function(String titleText, {required bool batchMode});

// How long a candidate title's search is given to resolve on its own
// before `_runQueueSearchStaggered` gets a head start on the next
// candidate title, instead of only starting it once the current one
// fully completes.
const Duration _kStaggerDelay = Duration(milliseconds: 500);

// Safety ceiling on how many candidate-title searches can be in flight at
// once for a single queue (batch-mode and episode-mode each get their own
// independent budget). The staggered loop below only ever looks one title
// ahead per iteration, so in practice this ceiling is essentially never
// reached for the typical 1-3 candidate titles (romaji/english/synonyms)
// — it exists purely as a defensive cap against a pathologically long
// synonyms list fanning out unbounded concurrent requests against
// nyaa.si's mirrors.
const int _kMaxConcurrentTitles = 3;

// In-memory TTL cache of scored torrent results, keyed by (anime id,
// episode). `AnimeDetailsScreen._torrentFutures` already memoizes
// per-episode within one screen instance, but `NavigationController`
// builds a brand-new `AnimeDetailsScreen` (and a brand-new
// `TorrentScraperService`) every time the user navigates away and back
// — this cache is what keeps a revisit within a few minutes from
// re-running the entire fetch/parse/score pipeline for data that almost
// certainly hasn't changed.
//
// Static (so it outlives any single `TorrentScraperService` instance),
// TTL-bounded, size-capped in-memory map, mirroring `_AnilistCache` in
// anilist_query_service.dart.
//
// Only ever populated on a successful, non-empty result — fetchTorrents
// throws on "no seeded torrents found," and that throw path never reaches
// `_TorrentSearchCache.set(...)`, so a transient failure is never cached
// and retried the same way.
class _TorrentCacheEntry {
  final List<Torrent> data;
  final DateTime expiresAt;
  const _TorrentCacheEntry(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

abstract final class _TorrentSearchCache {
  static final Map<String, _TorrentCacheEntry> _entries = {};

  // 5 minutes: long enough that "left and came back" navigation is
  // almost always a hit, short enough that seeder counts / newly-uploaded
  // releases don't go stale for an entire viewing session.
  static const Duration _ttl = Duration(minutes: 5);

  // Simple bound so a long browsing session can't grow this
  // unboundedly — evict the oldest entry once over the cap.
  static const int _maxEntries = 60;

  static String _keyFor(int animeId, int episodeNumber) =>
      '$animeId:$episodeNumber';

  static List<Torrent>? get(int animeId, int episodeNumber) {
    final key = _keyFor(animeId, episodeNumber);
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _entries.remove(key);
      return null;
    }
    return entry.data;
  }

  static void set(int animeId, int episodeNumber, List<Torrent> data) {
    if (_entries.length >= _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[_keyFor(animeId, episodeNumber)] = _TorrentCacheEntry(
      data,
      DateTime.now().add(_ttl),
    );
  }
}

/// Returns `true` if [future] completes (successfully OR with an error)
/// within [duration]; `false` if [duration] elapses first. Does NOT
/// consume or alter [future] itself in any way that would prevent the
/// caller from separately `await`-ing it afterward for its real
/// value/error — Futures support any number of independent listeners, and
/// the `onError` handler here deliberately does not rethrow, so this
/// listener chain is fully "handled" on its own regardless of what the
/// caller does with [future] later.
Future<bool> _completesWithin(Future<List<Torrent>> future, Duration duration) {
  final completer = Completer<bool>();
  final timer = Timer(duration, () {
    if (!completer.isCompleted) completer.complete(false);
  });

  unawaited(
    future.then(
      (_) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(true);
      },
      onError: (_) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(true);
      },
    ),
  );

  return completer.future;
}

/// Runs [trySearch] against each candidate title in [queue], preserving a
/// strict precedence contract: the first title (by list order, not by
/// which one happens to finish first) whose result is non-empty wins —
/// while not forcing title N+1 to wait for title N to fully complete
/// before it's even allowed to start.
///
/// How: title `i` is always awaited to completion before its result is
/// inspected (so a slow-but-earlier title can still override a
/// fast-but-later one). The only concurrency introduced: while waiting on
/// title `i`, if it hasn't resolved within [_kStaggerDelay], title `i+1`
/// is kicked off concurrently rather than waiting for `i` to finish. If
/// `i` later turns out non-empty, `i+1`'s speculative result is simply
/// discarded (never awaited for real) — its request still runs to
/// completion in the background, but nothing in this app is waiting on
/// it. If `i` turns out empty, `i+1` may already be finished (or partway
/// there) by the time this loop reaches it, hiding its latency behind
/// however long `i` took.
///
/// Deliberate trade-off, called out explicitly rather than buried in
/// code: because `package:http` gives no cheap way to cancel an in-flight
/// request once an earlier candidate wins, this means a genuinely higher
/// request volume against nyaa.si's mirrors on any search where an
/// earlier candidate title takes longer than [_kStaggerDelay] to resolve
/// — every such search fires (and lets run to completion) at least one
/// extra HTTP request it might not have needed. Accepted here because the
/// goal is minimizing click → magnet-link latency, not minimizing
/// request count.
Future<List<Torrent>> _runQueueSearchStaggered(
  List<String> queue, {
  required bool batchMode,
  required _TrySearchFn trySearch,
}) async {
  if (queue.isEmpty) return const [];

  final futures = List<Future<List<Torrent>>?>.filled(queue.length, null);

  Future<List<Torrent>> ensureStarted(int idx) {
    final existing = futures[idx];
    if (existing != null) return existing;

    final f = trySearch(queue[idx], batchMode: batchMode);
    futures[idx] = f;

    // Every future this function starts gets an always-attached,
    // error-swallowing listener the moment it's created — independent of
    // whether the loop below ever ends up `await`-ing it. This matters
    // for the speculative lookahead case: if title i resolves non-empty
    // and this function returns before the loop ever reaches i+1's
    // iteration, i+1's future would otherwise have zero listeners by the
    // time it eventually completes, and any error on it (e.g. all
    // mirrors down for that particular query) would be reported as an
    // unhandled Future error rather than silently discarded, which is
    // the correct behavior for a result nobody is waiting on.
    unawaited(f.catchError((_) => const <Torrent>[]));
    return f;
  }

  for (var i = 0; i < queue.length; i++) {
    final current = ensureStarted(i);

    final nextIdx = i + 1;
    final canLookAhead =
        nextIdx < queue.length &&
        futures.where((f) => f != null).length < _kMaxConcurrentTitles;

    if (canLookAhead) {
      final resolvedInTime = await _completesWithin(current, _kStaggerDelay);
      if (!resolvedInTime) {
        AppLogger.i(
          'TorrentScraper',
          'Title "${queue[i]}" slow to resolve — starting next candidate '
              '"${queue[nextIdx]}" concurrently (batchMode: $batchMode)',
        );
        unawaited(ensureStarted(nextIdx));
      }
    }

    final result = await current;
    if (result.isNotEmpty) return result;
    // Empty (not thrown) — fall through to i+1, which may already be
    // warm or finished thanks to the head start above.
  }

  return const [];
}

class TorrentScraperService {
  final http.Client _client;
  late final TorrentMirrorFetcher _mirrorFetcher;
  late final TsukihimeApiService _tsukihimeApi;
  late final TrackerScrapeService _trackerScrape;

  TorrentScraperService({
    http.Client? client,
    TsukihimeApiService? tsukihimeApi,
  }) : _client = client ?? http.Client() {
    _mirrorFetcher = TorrentMirrorFetcher(_client);
    _tsukihimeApi = tsukihimeApi ?? TsukihimeApiService();
    _trackerScrape = TrackerScrapeService(_client);
  }
  Future<List<Torrent>?> _tryTsukihime(Anime anime, int episodeNumber) async {
    try {
      final internalId = await _tsukihimeApi.resolveInternalId(anime.id);
      if (internalId == null) return null;
      final isFinished = anime.status?.toUpperCase() == "FINISHED";
      final isMovie = anime.format?.toUpperCase() == "MOVIE";
      final episodeFuture = _tsukihimeApi.getEpisodeTorrents(
        internalId,
        episodeNumber,
      );
      final seriesFuture = (isFinished && !isMovie)
          ? _tsukihimeApi.getSeriesTorrents(internalId)
          : Future.value(const <TsukihimeTorrentWire>[]);
      final wireResults = await Future.wait([episodeFuture, seriesFuture]);
      final episodeWires = wireResults[0];
      final batchWires = wireResults[1].where((w) => w.episodeNo == null);
      final seenIds = <String>{};
      final torrents = <Torrent>[];
      for (final wire in [...episodeWires, ...batchWires]) {
        if (wire.btih.isEmpty || wire.nyaaId == 0) {
          continue; //skip if no hash or not from nyaa.si
        }
        final torrent = wire.toAppTorrent();
        if (seenIds.add(torrent.id)) torrents.add(torrent);
      }
      if (torrents.isEmpty) return null;
      torrents.sort((a, b) => b.score.compareTo(a.score));
      return await _enrichTopCandidatesWithSeeders(torrents);
    } catch (e) {
      AppLogger.w(
        'TorrentScraper',
        'Tsukihime lookup failed, falling back to Nyaa: $e',
      );
      return null;
    }
  }

  static const int _kSeedersEnrichmentCount = 10;
  Future<List<Torrent>> _enrichTopCandidatesWithSeeders(
    List<Torrent> sorted,
  ) async {
    final top = sorted.take(_kSeedersEnrichmentCount).toList();
    final rest = sorted.skip(_kSeedersEnrichmentCount);
    try {
      final stats = await _trackerScrape.scrape(top.map((t) => t.id).toList());
      final enriched = top.map((t) {
        final stat = stats[t.id.toLowerCase()];
        if (stat == null) return t;
        return Torrent(
          id: t.id,
          title: t.title,
          releaseGroup: t.releaseGroup,
          resolution: t.resolution,
          size: t.size,
          seeders: stat.seeders,
          score: t.score + (math.log(stat.seeders + 1) * 5).clamp(0, 50),
          isBatch: t.isBatch,
        );
      }).toList();
      return [...enriched, ...rest]..sort((a, b) => b.score.compareTo(a.score));
    } catch (e) {
      AppLogger.w(
        'TorrentScraper',
        'Tracker scrape enrichment failed, using results as-is: $e',
      );
      return sorted;
    }
  }

  Future<List<Torrent>> fetchTorrents(Anime anime, int episodeNumber) async {
    // Cache check short-circuits the entire fetch/parse/score pipeline
    // (including the concurrent fan-out below) if this exact
    // (anime, episode) pair was resolved within the last few minutes.
    final cached = _TorrentSearchCache.get(anime.id, episodeNumber);
    if (cached != null) {
      AppLogger.i(
        'TorrentScraper',
        'Cache hit for ${anime.title.display} Episode $episodeNumber '
            '(${cached.length} candidates)',
      );
      return cached;
    }

    final tsukihimeResults = await _tryTsukihime(anime, episodeNumber);
    if (tsukihimeResults != null) {
      _TorrentSearchCache.set(anime.id, episodeNumber, tsukihimeResults);
      return tsukihimeResults;
    }

    final title = anime.title;
    final epStr = episodeNumber.toString().padLeft(2, '0');
    final isFinished = anime.status?.toUpperCase() == 'FINISHED';

    final format = anime.format?.toUpperCase();
    final isMovie = format == 'MOVIE';

    // 1. Build the search queue.
    final candidateTitles = <String>{};
    if (title.romaji != null && title.romaji!.isNotEmpty) {
      candidateTitles.add(title.romaji!);
    }
    if (title.english != null && title.english!.isNotEmpty) {
      candidateTitles.add(title.english!);
    }
    if (anime.synonyms != null) {
      candidateTitles.addAll(anime.synonyms!.where((s) => s.trim().isNotEmpty));
    }

    final searchQueue = candidateTitles.toList();

    final List<Torrent> batchResults;
    final List<Torrent> episodeResults;

    // 2. The search execution function.
    Future<List<Torrent>> trySearch(
      String titleText, {
      required bool batchMode,
    }) async {
      final safeTitle = titleText
          .replaceAll(_QueryRegex.stripTags, '')
          .replaceAll(_QueryRegex.punctuation, ' ')
          .replaceAll(_QueryRegex.whitespace, ' ')
          .trim();

      String buildQuery(String t) {
        if (isMovie || batchMode) {
          return t;
        } else {
          return '$t $epStr';
        }
      }

      AppLogger.i(
        'TorrentScraper',
        'Searching "${buildQuery(safeTitle)}" (batchMode: $batchMode)',
      );

      // The truncated-title fallback query fires concurrently with the
      // primary query; precedence is preserved by await order.
      final primaryFuture = _searchAndScore(
        searchQuery: buildQuery(safeTitle),
        animeTitle: titleText,
        episodeNumber: episodeNumber,
        totalEpisodes: anime.episodes,
        format: format,
        batchMode: batchMode,
      );

      final words = safeTitle.split(' ');
      Future<List<Torrent>>? fallbackFuture;
      if (words.length > 4) {
        final shortTitle = words.take(4).join(' ');
        AppLogger.i(
          'TorrentScraper',
          "Truncated fallback query (fired concurrently): '$shortTitle'",
        );
        fallbackFuture = _searchAndScore(
          searchQuery: buildQuery(shortTitle),
          animeTitle: titleText,
          episodeNumber: episodeNumber,
          totalEpisodes: anime.episodes,
          format: format,
          batchMode: batchMode,
        );
      }

      final primaryResult = await primaryFuture;
      if (primaryResult.isNotEmpty || fallbackFuture == null) {
        return primaryResult;
      }
      return await fallbackFuture;
    }

    // 3. Execute the queue. Batch-mode and episode-mode search are
    // independent axes, only ever concatenated+deduped+sorted afterward,
    // so they're fanned out via Future.wait instead of run strictly one
    // after another. Within each, candidate titles run via the staggered
    // scheduler above instead of strictly sequentially — see
    // `_runQueueSearchStaggered`'s doc comment for the precedence
    // guarantee and the request-volume trade-off it makes.
    final batchFuture = (isFinished && !isMovie)
        ? _runQueueSearchStaggered(
            searchQueue,
            batchMode: true,
            trySearch: trySearch,
          )
        : Future.value(const <Torrent>[]);
    final episodeFuture = _runQueueSearchStaggered(
      searchQueue,
      batchMode: false,
      trySearch: trySearch,
    );

    final results = await Future.wait([batchFuture, episodeFuture]);
    batchResults = results[0];
    episodeResults = results[1];

    // 4. Combine, deduplicate, and sort.
    final seenIds = <String>{};
    final combined = <Torrent>[];
    for (final t in [...batchResults, ...episodeResults]) {
      if (seenIds.add(t.id)) {
        combined.add(t);
      }
    }

    combined.sort((a, b) => b.score.compareTo(a.score));

    if (combined.isEmpty) {
      throw Exception(
        'No seeded torrents found for ${title.display} Episode $epStr',
      );
    }

    // Only successful, non-empty results are cached.
    _TorrentSearchCache.set(anime.id, episodeNumber, combined);

    return combined;
  }

  Future<List<Torrent>> _searchAndScore({
    required String searchQuery,
    required String animeTitle,
    required int episodeNumber,
    int? totalEpisodes,
    required String? format,
    required bool batchMode,
  }) async {
    final queryStr = Uri.encodeComponent(searchQuery);
    final batchParam = batchMode ? '&s=seeders&o=desc' : '';

    const mirrors = ['https://nyaa.si', 'https://nyaa.iss.one'];

    final http.Response response;
    try {
      response = await _mirrorFetcher.fetch(
        mirrors: mirrors,
        pathBuilder: (baseUrl) =>
            Uri.parse('$baseUrl/?page=rss&q=$queryStr&c=1_2&f=0$batchParam'),
      );
    } catch (e) {
      throw Exception('All Nyaa mirrors failed to respond. $e');
    }

    // Routed through the single, persistent TorrentParserWorker isolate
    // rather than a fresh compute() isolate spawned per call — see that
    // class's doc comment.
    final validTorrents = await TorrentParserWorker.instance.parseAndScore(
      xmlBody: response.body,
      animeTitle: animeTitle,
      episodeNumber: episodeNumber,
      totalEpisodes: totalEpisodes,
      format: format,
      batchMode: batchMode,
    );

    validTorrents.sort((a, b) => b.score.compareTo(a.score));
    AppLogger.i(
      'TorrentScraper',
      'Feed returned ${validTorrents.length} scored candidates',
    );
    return validTorrents;
  }

  void dispose() {
    _client.close();
    _tsukihimeApi.dispose();
    // Deliberately not touching TorrentParserWorker here — it's an
    // app-lifetime singleton shared across every TorrentScraperService
    // instance.
  }
}
