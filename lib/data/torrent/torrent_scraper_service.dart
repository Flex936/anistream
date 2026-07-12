// lib/data/torrent/torrent_scraper_service.dart
import 'dart:async';
import 'package:anistream/core/logging/app_logger.dart';
import 'package:http/http.dart' as http;

import '../anilist/models/anime.dart';
import 'models/torrent.dart';
import 'services/torrent_mirror_fetcher.dart';
import 'services/torrent_parser_worker.dart';

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

// ── Tier 4 tuning ────────────────────────────────────────────────────────
//
// How long a candidate title's search is given to resolve on its own
// before `_runQueueSearchStaggered` gets a head start on the NEXT
// candidate title, instead of only starting it once the current one
// fully completes.
const Duration _kStaggerDelay = Duration(milliseconds: 500);

// Safety ceiling on how many candidate-title searches can be in flight at
// once for a single queue (batch-mode and episode-mode each get their own
// independent budget). The staggered loop below only ever looks ONE title
// ahead per iteration, so in practice this ceiling is essentially never
// reached for the typical 1-3 candidate titles (romaji/english/synonyms)
// — it exists purely as a defensive cap against a pathologically long
// synonyms list fanning out unbounded concurrent requests against
// nyaa.si's mirrors.
const int _kMaxConcurrentTitles = 3;

// ── Tier 2: torrent-result cache ────────────────────────────────────────────
//
// `AnimeDetailsScreen._torrentFutures` already memoizes per-episode WITHIN
// one screen instance. What it can't cover: `NavigationController` builds a
// brand-new `AnimeDetailsScreen` (and therefore a brand-new
// `TorrentScraperService`) every time the user navigates away and back —
// autoplay falling through to manual selection, an accidental
// collapse/re-expand across a back/forward trip, revisiting a series a
// minute later. Each of those re-ran the entire fetchTorrents pipeline for
// data that almost certainly hadn't changed.
//
// Mirrors `_AnilistCache` in anilist_query_service.dart: a static (so it
// outlives any single `TorrentScraperService` instance), TTL-bounded,
// size-capped in-memory map, keyed by (anime id, episode) — the pair that
// fully determines fetchTorrents' output today.
//
// Only ever populated on a successful, non-empty result — fetchTorrents
// throws on "no seeded torrents found," and that throw path never reaches
// the `_TorrentSearchCache.set(...)` call, so a transient failure is never
// cached and retried the same way.
class _TorrentCacheEntry {
  final List<Torrent> data;
  final DateTime expiresAt;
  const _TorrentCacheEntry(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

abstract final class _TorrentSearchCache {
  static final Map<String, _TorrentCacheEntry> _entries = {};

  // ── 5 minutes: long enough that "left and came back" navigation is
  // almost always a hit, short enough that seeder counts / newly-uploaded
  // releases don't go stale for an entire viewing session. ──
  static const Duration _ttl = Duration(minutes: 5);

  // ── Simple bound so a long browsing session can't grow this
  // unboundedly — evict the oldest entry once over the cap. ──
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

  future.then(
    (_) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(true);
    },
    onError: (_) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(true);
    },
  );

  return completer.future;
}

/// Tier 4: runs [trySearch] against each candidate title in [queue],
/// preserving the EXACT same precedence contract Tier 1-3's
/// `_runQueueSearch` had — the first title (by LIST ORDER, not by which
/// one happens to finish first) whose result is non-empty wins — while
/// no longer forcing title N+1 to wait for title N to fully complete
/// before it's even allowed to start.
///
/// How: title `i` is always awaited to completion before its result is
/// inspected (so a slow-but-earlier title can still override a
/// fast-but-later one, exactly as before). The only change is that WHILE
/// waiting on title `i`, if it hasn't resolved within [_kStaggerDelay],
/// title `i+1` is kicked off concurrently rather than only being started
/// once `i` is done. If `i` later turns out non-empty, `i+1`'s
/// speculative result is simply discarded (never awaited for real) — its
/// request still runs to completion in the background, but nothing in
/// this app is waiting on it. If `i` turns out empty, `i+1` may already
/// be finished (or partway there) by the time this loop reaches it,
/// hiding its latency behind however long `i` took.
///
/// Deliberate trade-off, called out explicitly rather than buried in
/// code: because `package:http` gives no cheap way to cancel an in-flight
/// request once an earlier candidate wins, this means a genuinely higher
/// request volume against nyaa.si's mirrors on any search where an
/// earlier candidate title takes longer than [_kStaggerDelay] to resolve
/// — every such search now fires (and lets run to completion) at least
/// one extra HTTP request it might not have needed. Accepted here because
/// the stated goal is minimizing click → magnet-link latency, not
/// minimizing request count.
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

    // ── Every future this function starts gets an always-attached,
    // error-swallowing listener the moment it's created — independent of
    // whether the loop below ever ends up `await`-ing it "for real". This
    // matters specifically for the SPECULATIVE lookahead case: if title i
    // resolves non-empty and we return before the loop ever reaches
    // i+1's iteration, i+1's future would otherwise have zero listeners
    // by the time it eventually completes, and any error on it (e.g. all
    // mirrors down for that particular query) would be reported as an
    // unhandled Future error rather than silently discarded, which is the
    // correct behavior for a result nobody is waiting on. ──
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
        ensureStarted(nextIdx);
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

  TorrentScraperService({http.Client? client})
    : _client = client ?? http.Client() {
    _mirrorFetcher = TorrentMirrorFetcher(_client);
  }

  Future<List<Torrent>> fetchTorrents(Anime anime, int episodeNumber) async {
    // ── Tier 2 cache check — short-circuits the entire fetch/parse/score
    // pipeline (including Tier 1/4's concurrent fan-out) if this exact
    // (anime, episode) pair was resolved within the last few minutes. ──
    final cached = _TorrentSearchCache.get(anime.id, episodeNumber);
    if (cached != null) {
      AppLogger.i(
        'TorrentScraper',
        'Cache hit for ${anime.title.display} Episode $episodeNumber '
            '(${cached.length} candidates)',
      );
      return cached;
    }

    final title = anime.title;
    final epStr = episodeNumber.toString().padLeft(2, '0');
    final isFinished = anime.status?.toUpperCase() == 'FINISHED';

    final format = anime.format?.toUpperCase();
    final isMovie = format == 'MOVIE';

    // ── 1. Build the Search Queue ──
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

    // ── 2. The Search Execution Function ──
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

      // ── Tier 1b: truncated-title fallback fires concurrently with the
      // primary query; precedence is preserved by await order. ──
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

    // ── 3. Execute the Queue ──
    // Tier 1a: batch-mode and episode-mode search are independent axes,
    // only ever concatenated+deduped+sorted afterward, so they're fanned
    // out via Future.wait instead of run strictly one after another.
    //
    // Tier 4: within EACH of those two queues, candidate titles are run
    // via the staggered scheduler above instead of strictly sequentially
    // — see `_runQueueSearchStaggered`'s doc comment for the precedence
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

    // ── 4. Combine, Deduplicate, and Sort ──
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

    // ── Tier 2: only successful, non-empty results are cached. ──
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

    // ── Tier 3: routed through the single, persistent TorrentParserWorker
    // isolate instead of a fresh compute() isolate spawned per call. ──
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
    // ── Deliberately NOT touching TorrentParserWorker here — it's an
    // app-lifetime singleton shared across every TorrentScraperService
    // instance. ──
  }
}
