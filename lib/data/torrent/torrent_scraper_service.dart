import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:anistream/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../anilist/models/anime.dart';
import 'models/torrent.dart';
import 'services/torrent_parser.dart';

abstract final class _QueryRegex {
  static final extractSeason = RegExp(
    r'(?:season\s*(\d+)|\bs(\d+)\b)',
    caseSensitive: false,
  );
  static final stripTags = RegExp(
    r'(?:season\s*\d+|\bs\d+\b|part\s*\d+|cour\s*\d+)',
    caseSensitive: false,
  );
  static final punctuation = RegExp(r"[:!?',\-.]");
  static final whitespace = RegExp(r'\s+');
}

// ── Single-argument payload for compute(). A Record instead of a class —
// it's a disposable, fields-only carrier, so there's no need for a
// constructor/boilerplate, and Records are exactly what Dart 3 added for
// this kind of "bag of values passed across an isolate boundary" use case. ──
typedef _FeedParseRequest = ({
  String xmlBody,
  String animeTitle,
  int episodeNumber,
  int? totalEpisodes,
  String? format,
  bool batchMode,
});

// ── Everything _scoreItem needs that does NOT vary per RSS item. Computed
// once per feed in _parseAndScoreFeed and handed to every _scoreItem call,
// instead of being recomputed from scratch for every single item (see the
// note at the call site for why that mattered). ──
typedef _ScoringContext = ({
  String animeTitleLower,
  bool hasFinalSeason,
  bool isMovie,
  bool isOvaFormat,
  int targetSeason,
  int episodeNumber,
  int? totalEpisodes,
  bool batchMode,
});

// ── Fields pulled out of a single <item> in one pass over its children,
// instead of 5 separate item.findElements(name).firstOrNull calls (each of
// which re-walks the item's child list from the start). ──
typedef _RawItemFields = ({
  String title,
  String? infoHash,
  String size,
  int seeders,
  bool isTrusted,
});

// ── Moved off UI thread ──
List<Torrent> _parseAndScoreFeed(_FeedParseRequest req) {
  late final XmlDocument document;
  try {
    document = XmlDocument.parse(req.xmlBody);
  } catch (_) {
    throw Exception('Failed to parse Nyaa RSS feed: invalid XML.');
  }

  final items = document.findAllElements('item');

  final seasonMatch = _QueryRegex.extractSeason.firstMatch(req.animeTitle);
  final targetSeason = seasonMatch != null
      ? (int.tryParse(seasonMatch.group(1) ?? seasonMatch.group(2) ?? '1') ?? 1)
      : 1;

  // animeTitle.toLowerCase(), the "final season" check on it, and the
  // format-derived flags are all the same for every item in this feed —
  // the original recomputed `ql = animeTitle.toLowerCase()` and
  // `hasFinal = ql.contains('final season')` *inside* _scoreItem, i.e.
  // once per RSS item (50-300 times per search) instead of once per feed.
  // `targetSeason` had already been hoisted out exactly like this; this
  // just extends the same treatment to the rest of the per-feed constants.
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
  // (Dropped `epStr` entirely — the original computed it once and threaded
  // it through every _scoreItem call as a required parameter, but nothing
  // inside _scoreItem ever actually read it. Pure dead weight.)

  final validTorrents = <Torrent>[];
  for (final item in items) {
    final torrent = TorrentScraperService._scoreItem(item, ctx);
    if (torrent != null) {
      validTorrents.add(torrent);
    }
  }
  return validTorrents;
}

class TorrentScraperService {
  final http.Client _client;

  TorrentScraperService({http.Client? client})
    : _client = client ?? http.Client();

  // ── Convert Nyaa string (e.g. "1.2 GiB") to raw Megabytes ──
  //
  // Left as a regex deliberately: the input is always a tiny, fixed-format
  // string straight from the feed (rarely more than ~10 chars), and the
  // pattern has no backtracking risk (simple character classes only), so
  // there's no measurable win available here — and a hand-rolled version
  // would have to carefully replicate the "must end in a literal 'b'"
  // requirement to stay behaviorally identical. Not worth the risk for a
  // sub-microsecond operation.
  static double _parseSizeToMB(String sizeStr) {
    final lower = sizeStr.toLowerCase().trim();
    final match = RegExp(r'([\d.]+)\s*([kmg]i?b)').firstMatch(lower);
    if (match == null) return 0.0;

    final value = double.tryParse(match.group(1)!) ?? 0.0;
    return switch (match.group(2)!) {
      final u when u.contains('g') => value * 1024,
      final u when u.contains('m') => value,
      final u when u.contains('k') => value / 1024,
      _ => 0.0,
    };
  }

  Future<List<Torrent>> fetchTorrents(Anime anime, int episodeNumber) async {
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

    List<Torrent> batchResults = [];
    List<Torrent> episodeResults = [];

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
      var found = await _searchAndScore(
        searchQuery: buildQuery(safeTitle),
        animeTitle: titleText,
        episodeNumber: episodeNumber,
        totalEpisodes: anime.episodes,
        format: format,
        batchMode: batchMode,
      );

      if (found.isEmpty) {
        final words = safeTitle.split(' ');
        if (words.length > 4) {
          final shortTitle = words.take(4).join(' ');
          AppLogger.i(
            'TorrentScraper',
            "Truncated fallback query: '$shortTitle'",
          );
          found = await _searchAndScore(
            searchQuery: buildQuery(shortTitle),
            animeTitle: titleText,
            episodeNumber: episodeNumber,
            totalEpisodes: anime.episodes,
            format: format,
            batchMode: batchMode,
          );
        }
      }
      return found;
    }

    // ── 3. Execute the Queue ──
    // (Left sequential/short-circuiting on purpose — see write-up. Firing
    // these concurrently would change which mirror/title "wins" and load
    // nyaa.si's mirrors harder for no guaranteed benefit, which is a real
    // behavior change, not a pure performance one.)
    if (isFinished && !isMovie) {
      for (final t in searchQueue) {
        batchResults = await trySearch(t, batchMode: true);
        if (batchResults.isNotEmpty) {
          break;
        }
      }
    }

    for (final t in searchQueue) {
      episodeResults = await trySearch(t, batchMode: false);
      if (episodeResults.isNotEmpty) {
        break;
      }
    }

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

    // ── Fallback Mirror List ──
    const mirrors = ['https://nyaa.si', 'https://nyaa.iss.one'];

    http.Response? response;
    Exception? lastException;

    // Loop through the mirrors until one works
    for (final baseUrl in mirrors) {
      final feedUrl = Uri.parse(
        '$baseUrl/?page=rss&q=$queryStr&c=1_2&f=0$batchParam',
      );

      try {
        final res = await _client
            .get(feedUrl)
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          response = res;
          break; // ── Exit the loop early ──
        } else {
          lastException = Exception('HTTP ${res.statusCode}');
          AppLogger.w(
            'TorrentScraper',
            'Mirror $baseUrl failed with HTTP ${res.statusCode}, trying next mirror',
          );
        }
      } on SocketException {
        lastException = Exception('DNS/Network Block');
        AppLogger.w(
          'TorrentScraper',
          ' Mirror $baseUrl is blocked or unreachable (SocketException). Trying next...',
        );
      } on TimeoutException {
        lastException = Exception('Connection Timeout');
        AppLogger.w(
          'TorrentScraper',
          ' Mirror $baseUrl timed out. Trying next...',
        );
      } catch (e) {
        lastException = Exception(e.toString());
        AppLogger.w('TorrentScraper', ' Mirror $baseUrl failed: $e');
      }
    }

    // If the loop finished and response is still null, literally every mirror is blocked/down.
    if (response == null) {
      throw Exception(
        'All Nyaa mirrors failed to respond. Last error: ${lastException?.toString()}',
      );
    }

    final validTorrents = await compute(_parseAndScoreFeed, (
      xmlBody: response.body,
      animeTitle: animeTitle,
      episodeNumber: episodeNumber,
      totalEpisodes: totalEpisodes,
      format: format,
      batchMode: batchMode,
    ));

    validTorrents.sort((a, b) => b.score.compareTo(a.score));
    AppLogger.i(
      'TorrentScraper',
      'Feed returned ${validTorrents.length} scored candidates',
    );
    return validTorrents;
  }

  // ── One pass over item.childElements instead of 5 separate
  // findElements(name).firstOrNull calls. Each findElements() call walks
  // the item's child list from the start looking for one tag name; doing
  // that 5 times per item means up to 5x the tree-walking work for a
  // ~15-element child list, repeated for every item in the feed. This
  // walks the children once and switches on the qualified tag name,
  // converting seeders/trusted to their final int/bool form inline so
  // _scoreItem doesn't have to parse them again. First occurrence of each
  // tag wins, matching `firstOrNull`'s semantics exactly. ──
  static _RawItemFields _extractItemFields(XmlElement item) {
    var title = '';
    String? infoHash;
    var size = '0 MiB';
    var seeders = 0;
    var isTrusted = false;

    var hasTitle = false;
    var hasInfoHash = false;
    var hasSize = false;
    var hasSeeders = false;
    var hasTrusted = false;

    for (final child in item.childElements) {
      switch (child.name.qualified) {
        case 'title':
          if (!hasTitle) {
            title = child.innerText;
            hasTitle = true;
          }
        case 'nyaa:infoHash':
          if (!hasInfoHash) {
            infoHash = child.innerText;
            hasInfoHash = true;
          }
        case 'nyaa:size':
          if (!hasSize) {
            size = child.innerText;
            hasSize = true;
          }
        case 'nyaa:seeders':
          if (!hasSeeders) {
            seeders = int.tryParse(child.innerText) ?? 0;
            hasSeeders = true;
          }
        case 'nyaa:trusted':
          if (!hasTrusted) {
            isTrusted = child.innerText.toLowerCase() == 'yes';
            hasTrusted = true;
          }
      }
    }

    return (
      title: title,
      infoHash: infoHash,
      size: size,
      seeders: seeders,
      isTrusted: isTrusted,
    );
  }

  static Torrent? _scoreItem(XmlElement item, _ScoringContext ctx) {
    final fields = _extractItemFields(item);

    if (fields.infoHash == null || fields.infoHash!.isEmpty) {
      return null;
    }

    if (fields.seeders == 0) {
      return null;
    }

    final rawTitle = fields.title;
    final meta = TorrentParser.parse(rawTitle);

    double score = 100.0;
    final tl = rawTitle.toLowerCase();

    // 1. Batch & Season Filtering — scoring math byte-for-byte unchanged.
    if (ctx.batchMode) {
      if (!meta.isBatch) {
        return null;
      }
      if (meta.season != ctx.targetSeason) {
        return null;
      }

      score += 100;

      if (meta.batchStart != -1 && meta.batchEnd != -1) {
        if (meta.batchStart <= 1 &&
            ctx.totalEpisodes != null &&
            meta.batchEnd >= ctx.totalEpisodes!) {
          score += 20;
        } else if (meta.batchStart > ctx.episodeNumber ||
            meta.batchEnd < ctx.episodeNumber) {
          return null;
        }
      }
    } else {
      if (meta.isBatch) {
        score -= 150;
      }

      if (meta.season == ctx.targetSeason) {
        score += 100;
      } else {
        score -= 100;
      }

      // 2. Episode Filtering
      if (!ctx.isMovie) {
        if (meta.episode != -1 && meta.episode != ctx.episodeNumber) {
          return null;
        }
      } else {
        if (meta.episode != -1 && meta.episode != 1) {
          return null;
        }
      }
    }

    // 3. Final Season tagging — ctx.hasFinalSeason is the same precomputed
    // value for every item in this feed; only `torrentFinal` (which
    // depends on this specific item's title) still needs to be computed
    // per item.
    final torrentFinal = tl.contains('final season');

    if (ctx.hasFinalSeason && torrentFinal) {
      score += 100;
    } else if (!ctx.hasFinalSeason && torrentFinal) {
      score -= 100;
    }

    // 4. Movies / OVAs Formatting Logic
    // `const` so this list is allocated once for the whole app, not once
    // per item scored (the original literal allocated a fresh growable
    // List on every single _scoreItem call).
    for (final tag in const ['ova', 'ona', 'oad', 'special']) {
      if (!ctx.isOvaFormat &&
          !ctx.animeTitleLower.contains(tag) &&
          tl.contains(tag)) {
        score -= 100;
      } else if (ctx.isOvaFormat && tl.contains(tag)) {
        score += 50;
      }
    }

    if (!ctx.isMovie && tl.contains('movie')) {
      score -= 100;
    } else if (ctx.isMovie &&
        (tl.contains('movie') ||
            tl.contains('gekijouban') ||
            tl.contains('film'))) {
      score += 50;
    }

    // Language Tags
    /* if (tl.contains('dual audio')) {
      score += 40;
    }
    if (tl.contains('multi-sub') || tl.contains('multisub')) {
      score += 20;
    } */

    // 5. Codec & Resolution Quality Modifiers
    if (meta.resolution == '1080p') {
      score += 20;
    } else if (meta.resolution == '720p') {
      score += 10;
    }

    if (tl.contains('av1')) {
      score += 30;
    } else if (tl.contains('hevc') ||
        tl.contains('x265') ||
        tl.contains('h.265')) {
      score += 20;
    } else if (tl.contains('avc') ||
        tl.contains('x264') ||
        tl.contains('h.264')) {
      score += 5;
    }

    if (tl.contains('10bit') || tl.contains('10-bit')) {
      score += 15;
    }
    if (tl.contains('opus')) {
      score += 15;
    }
    if (tl.contains('webrip')) {
      score += 10;
    } else if (tl.contains('web-dl') || tl.contains('webdl')) {
      score += 5;
    }

    // 6. Trusted Groups
    if (fields.isTrusted) {
      score += 30;
    }

    // 7. Logarithmic Seeder Algorithm
    score += (math.log(fields.seeders + 1) * 5).clamp(0, 50);

    // ── GOLDILOCKS SIZE-TO-BITRATE CURVE ──
    final sizeMB = _parseSizeToMB(fields.size);

    if (sizeMB > 0) {
      double avgEpSizeMB = sizeMB;

      if (meta.isBatch) {
        int epCount = 1;
        if (meta.batchStart != -1 &&
            meta.batchEnd != -1 &&
            meta.batchEnd >= meta.batchStart) {
          epCount = (meta.batchEnd - meta.batchStart) + 1;
        } else if (ctx.totalEpisodes != null && ctx.totalEpisodes! > 0) {
          epCount = ctx.totalEpisodes!;
        } else {
          epCount = 12; // Fallback assumption: a standard 1-cour season
        }
        avgEpSizeMB = sizeMB / epCount;
      }

      if (ctx.isMovie) {
        if (avgEpSizeMB < 800) {
          score -= 30;
        } else if (avgEpSizeMB >= 1500 && avgEpSizeMB <= 6000) {
          score += 30;
        } else if (avgEpSizeMB > 10000) {
          score -= 40;
        }
      } else {
        if (avgEpSizeMB < 150) {
          score -= 30;
        } else if (avgEpSizeMB >= 250 && avgEpSizeMB <= 1200) {
          score += 30;
        } else if (avgEpSizeMB >= 150 && avgEpSizeMB < 250) {
          score += 10;
        } else if (avgEpSizeMB > 1200 && avgEpSizeMB <= 2500) {
          score += 10;
        } else if (avgEpSizeMB > 2500) {
          score -= 30;
        }
      }
    }

    return Torrent(
      id: fields.infoHash!,
      title: rawTitle,
      releaseGroup: meta.releaseGroup,
      resolution: meta.resolution,
      size: fields.size,
      seeders: fields.seeders,
      score: score,
      isBatch: meta.isBatch,
    );
  }

  void dispose() {
    _client.close();
  }
}
