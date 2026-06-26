import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
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

class _FeedParseRequest {
  final String xmlBody;
  final String animeTitle;
  final int episodeNumber;
  final int? totalEpisodes;
  final String? format;
  final bool batchMode;

  const _FeedParseRequest({
    required this.xmlBody,
    required this.animeTitle,
    required this.episodeNumber,
    this.totalEpisodes,
    required this.format,
    required this.batchMode,
  });
}

// ── Moved off UI thread ──
List<Torrent> _parseAndScoreFeed(_FeedParseRequest req) {
  late XmlDocument document;
  try {
    document = XmlDocument.parse(req.xmlBody);
  } catch (e) {
    throw Exception('Failed to parse Nyaa RSS feed: invalid XML.');
  }

  final items = document.findAllElements('item');
  final epStr = req.episodeNumber.toString().padLeft(2, '0');

  final seasonMatch = _QueryRegex.extractSeason.firstMatch(req.animeTitle);
  final targetSeason = seasonMatch != null
      ? (int.tryParse(seasonMatch.group(1) ?? seasonMatch.group(2) ?? '1') ?? 1)
      : 1;

  final List<Torrent> validTorrents = [];

  for (final item in items) {
    final torrent = TorrentScraperService._scoreItem(
      item: item,
      animeTitle: req.animeTitle,
      episodeNumber: req.episodeNumber,
      epStr: epStr,
      targetSeason: targetSeason,
      totalEpisodes: req.totalEpisodes,
      format: req.format,
      batchMode: req.batchMode,
    );
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
  static double _parseSizeToMB(String sizeStr) {
    final lower = sizeStr.toLowerCase().trim();
    final regex = RegExp(r'([\d.]+)\s*([kmg]i?b)');
    final match = regex.firstMatch(lower);

    if (match == null) {
      return 0.0;
    }

    final value = double.tryParse(match.group(1)!) ?? 0.0;
    final unit = match.group(2)!;

    if (unit.contains('g')) {
      return value * 1024;
    }
    if (unit.contains('m')) {
      return value;
    }
    if (unit.contains('k')) {
      return value / 1024;
    }

    return 0.0;
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
          log("[Scraper] Truncated fallback query: '$shortTitle'");
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
    final feedUrl = Uri.parse(
      'https://nyaa.si/?page=rss&q=$queryStr&c=1_2&f=0$batchParam',
    );

    http.Response response;
    try {
      response = await _client
          .get(feedUrl)
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      throw Exception('Network error while searching Nyaa.si.');
    } on TimeoutException {
      throw Exception('Connection timed out while reaching Nyaa.si.');
    }

    if (response.statusCode != 200) {
      throw Exception('Nyaa returned HTTP ${response.statusCode}');
    }

    final validTorrents = await compute(
      _parseAndScoreFeed,
      _FeedParseRequest(
        xmlBody: response.body,
        animeTitle: animeTitle,
        episodeNumber: episodeNumber,
        totalEpisodes: totalEpisodes,
        format: format,
        batchMode: batchMode,
      ),
    );

    validTorrents.sort((a, b) => b.score.compareTo(a.score));
    return validTorrents;
  }

  static Torrent? _scoreItem({
    required XmlElement item,
    required String animeTitle,
    required int episodeNumber,
    required String epStr,
    required int targetSeason,
    int? totalEpisodes,
    required String? format,
    required bool batchMode,
  }) {
    final rawTitle = item.findElements('title').firstOrNull?.innerText ?? '';
    final infoHash = item.findElements('nyaa:infoHash').firstOrNull?.innerText;
    final sizeStr =
        item.findElements('nyaa:size').firstOrNull?.innerText ?? '0 MiB';
    final seedersStr =
        item.findElements('nyaa:seeders').firstOrNull?.innerText ?? '0';
    final trustedStr =
        item.findElements('nyaa:trusted').firstOrNull?.innerText ?? 'No';

    final isTrusted = trustedStr.toLowerCase() == 'yes';

    if (infoHash == null || infoHash.isEmpty) {
      return null;
    }

    final seedCount = int.tryParse(seedersStr) ?? 0;
    if (seedCount == 0) {
      return null;
    }

    final meta = TorrentParser.parse(rawTitle);

    double score = 100.0;
    final tl = rawTitle.toLowerCase();
    final ql = animeTitle.toLowerCase();

    final isMovie = format == 'MOVIE';
    final isOvaFormat =
        format == 'OVA' || format == 'ONA' || format == 'SPECIAL';

    // 1. Batch & Season Filtering
    if (batchMode) {
      if (!meta.isBatch) {
        return null;
      }
      if (meta.season != targetSeason) {
        return null;
      }

      score += 100;

      if (meta.batchStart != -1 && meta.batchEnd != -1) {
        if (meta.batchStart <= 1 &&
            totalEpisodes != null &&
            meta.batchEnd >= totalEpisodes) {
          score += 20;
        } else if (meta.batchStart > episodeNumber ||
            meta.batchEnd < episodeNumber) {
          return null;
        }
      }
    } else {
      if (meta.isBatch) {
        score -= 150;
      }

      if (meta.season == targetSeason) {
        score += 100;
      } else {
        score -= 100;
      }

      // 2. Episode Filtering
      if (!isMovie) {
        if (meta.episode != -1 && meta.episode != episodeNumber) {
          return null;
        }
      } else {
        if (meta.episode != -1 && meta.episode != 1) {
          return null;
        }
      }
    }

    // 3. Final Season tagging
    final hasFinal = ql.contains('final season');
    final torrentFinal = tl.contains('final season');

    if (hasFinal && torrentFinal) {
      score += 100;
    } else if (!hasFinal && torrentFinal) {
      score -= 100;
    }

    // 4. Movies / OVAs Formatting Logic
    for (final tag in ['ova', 'ona', 'oad', 'special']) {
      if (!isOvaFormat && !ql.contains(tag) && tl.contains(tag)) {
        score -= 100;
      } else if (isOvaFormat && tl.contains(tag)) {
        score += 50;
      }
    }

    if (!isMovie && tl.contains('movie')) {
      score -= 100;
    } else if (isMovie &&
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
    if (isTrusted) {
      score += 30;
    }

    // 7. Logarithmic Seeder Algorithm
    score += (math.log(seedCount + 1) * 5).clamp(0, 50);

    // ── GOLDILOCKS SIZE-TO-BITRATE CURVE ──
    final sizeMB = _parseSizeToMB(sizeStr);

    if (sizeMB > 0) {
      double avgEpSizeMB = sizeMB;

      // If it's a batch, find the episode count to get the per-episode average
      if (meta.isBatch) {
        int epCount = 1;
        if (meta.batchStart != -1 &&
            meta.batchEnd != -1 &&
            meta.batchEnd >= meta.batchStart) {
          epCount = (meta.batchEnd - meta.batchStart) + 1;
        } else if (totalEpisodes != null && totalEpisodes > 0) {
          epCount = totalEpisodes;
        } else {
          epCount = 12; // Fallback assumption: a standard 1-cour season
        }
        avgEpSizeMB = sizeMB / epCount;
      }

      // Apply the Curve
      if (isMovie) {
        // Movies (approx. 4x episode length)
        if (avgEpSizeMB < 800) {
          score -= 30; // Bitrate starved (< 800MB)
        } else if (avgEpSizeMB >= 1500 && avgEpSizeMB <= 6000) {
          score += 30; // Goldilocks Zone (1.5GB to 6GB)
        } else if (avgEpSizeMB > 10000) {
          score -= 40; // Buffering nightmare (> 10GB)
        }
      } else {
        // Standard TV Episode
        if (avgEpSizeMB < 150) {
          score -= 30; // Bitrate starved (< 150MB)
        } else if (avgEpSizeMB >= 250 && avgEpSizeMB <= 1200) {
          score += 30; // Goldilocks Zone (250MB to 1.2GB)
        } else if (avgEpSizeMB >= 150 && avgEpSizeMB < 250) {
          score += 10; // Acceptable but low
        } else if (avgEpSizeMB > 1200 && avgEpSizeMB <= 2500) {
          score += 10; // High quality but bulky
        } else if (avgEpSizeMB > 2500) {
          score -= 30; // Buffering nightmare (> 2.5GB)
        }
      }
    }

    return Torrent(
      id: infoHash,
      title: rawTitle,
      releaseGroup: meta.releaseGroup,
      resolution: meta.resolution,
      size: sizeStr,
      seeders: seedCount,
      magnetLink: _buildMagnet(infoHash, rawTitle),
      score: score,
      isBatch: meta.isBatch,
    );
  }

  static String _buildMagnet(String infoHash, String title) {
    var link = 'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}';
    const trackers = [
      "http://nyaa.tracker.wf:7777/announce",
      "udp://tracker.opentrackr.org:1337/announce",
      "udp://exodus.desync.com:6969/announce",
    ];
    for (final tr in trackers) {
      link += '&tr=${Uri.encodeComponent(tr)}';
    }
    return link;
  }

  void dispose() {
    _client.close();
  }
}
