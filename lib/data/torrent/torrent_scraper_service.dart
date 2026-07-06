import 'dart:async';
import 'package:anistream/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../anilist/models/anime.dart';
import 'models/torrent.dart';
import 'services/torrent_mirror_fetcher.dart';
import 'services/torrent_scoring_engine.dart';

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

// ── Single-argument payload for compute(). ──
typedef _FeedParseRequest = ({
  String xmlBody,
  String animeTitle,
  int episodeNumber,
  int? totalEpisodes,
  String? format,
  bool batchMode,
});

// ── Moved off UI thread. Actual per-item scoring now lives in
// TorrentScoringEngine — this function's remaining job is parsing the feed
// and building the per-feed ScoringContext exactly once. ──
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

class TorrentScraperService {
  final http.Client _client;
  late final TorrentMirrorFetcher _mirrorFetcher;

  TorrentScraperService({http.Client? client})
    : _client = client ?? http.Client() {
    _mirrorFetcher = TorrentMirrorFetcher(_client);
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
    // (Left sequential/short-circuiting on purpose — firing these
    // concurrently would change which mirror/title "wins" and load
    // nyaa.si's mirrors harder for no guaranteed benefit.)
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

  void dispose() {
    _client.close();
  }
}
