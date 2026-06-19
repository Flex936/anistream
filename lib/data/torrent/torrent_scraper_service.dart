import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../anilist/models/anime.dart'; 
import 'models/torrent.dart';

abstract final class _Regex {
  static final whitespace = RegExp(r'\s+');
  static final punct = RegExp(r"[:!?',\-.]"); 
  static final season = RegExp(r'(?:season\s*(\d+)|\bs(\d+)\b|(\d+)(?:st|nd|rd|th)\s+season|(?:part|cour)\s*(\d+))', caseSensitive: false);
  static final ep1 = RegExp(r'(?:e|ep|episode)\s*(\d+)', caseSensitive: false);
  static final ep2 = RegExp(r'\s+-\s+(\d+)(?:v\d)?\s+');
  static final ep3 = RegExp(r'\s+(0\d+)\s+');
  static final batch = RegExp(r'\d{2,}\s*[-~]\s*\d{2,}');
  static final group = RegExp(r'^\[(.*?)\]');
  static final resolution = RegExp(r'(1080p|720p|480p|2160p|4K)', caseSensitive: false);
}

class TorrentScraperService {
  final http.Client _client;

  TorrentScraperService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Torrent>> fetchTorrents(AnimeTitle title, int episodeNumber) async {
    final epStr = episodeNumber.toString().padLeft(2, '0');
    List<Torrent> results = [];

    Future<void> trySearch(String titleText, bool isMovie) async {
      if (results.isNotEmpty) return; 

      final safeTitle = titleText
          .replaceAll(_Regex.season, '')
          .replaceAll(_Regex.punct, ' ')
          .replaceAll(_Regex.whitespace, ' ')
          .trim();

      results = await _searchAndScore(
        searchQuery: isMovie ? safeTitle : '$safeTitle $epStr',
        animeTitle: titleText,
        episodeNumber: episodeNumber,
        isMovieFallback: isMovie,
      );

      if (results.isEmpty) {
        final words = safeTitle.split(' ');
        if (words.length > 4) {
          final shortTitle = words.take(4).join(' ');
          log("[Scraper] Truncated fallback query: '$shortTitle'");
          results = await _searchAndScore(
            searchQuery: isMovie ? shortTitle : '$shortTitle $epStr',
            animeTitle: titleText,
            episodeNumber: episodeNumber,
            isMovieFallback: isMovie,
          );
        }
      }
    }
    
    if (title.romaji != null) await trySearch(title.romaji!, false);
    if (title.english != null) await trySearch(title.english!, false);
    
    if (episodeNumber == 1) {
      if (title.romaji != null) await trySearch(title.romaji!, true);
      if (title.english != null) await trySearch(title.english!, true);
    }

    if (results.isEmpty) {
      throw Exception('No seeded torrents found for ${title.display} Episode $epStr');
    }

    return results;
  }

  Future<List<Torrent>> _searchAndScore({
    required String searchQuery,
    required String animeTitle,
    required int episodeNumber,
    required bool isMovieFallback,
  }) async {
    final feedUrl = Uri.parse('https://nyaa.si/?page=rss&q=${Uri.encodeComponent(searchQuery)}&c=1_2&f=0');
    log("[Scraper] Nyaa query: $searchQuery");

    http.Response response;
    try {
      response = await _client.get(feedUrl).timeout(const Duration(seconds: 15));
    } on SocketException {
      throw Exception('Network error while searching Nyaa.si.');
    } on TimeoutException {
      throw Exception('Connection timed out while reaching Nyaa.si.');
    }

    if (response.statusCode != 200) {
      throw Exception('Nyaa returned HTTP ${response.statusCode}');
    }

    late XmlDocument document;
    try {
      document = XmlDocument.parse(response.body);
    } catch (e) {
      throw Exception('Failed to parse Nyaa RSS feed: invalid XML.');
    }

    final items = document.findAllElements('item');
    final titleLow = animeTitle.toLowerCase();
    final targetSeason = _extractSeason(titleLow);
    final epStr = episodeNumber.toString().padLeft(2, '0');

    final isMovieQuery = isMovieFallback || titleLow.contains('movie') || titleLow.contains('film') || titleLow.contains('gekijouban');
    final List<Torrent> validTorrents = [];

    for (final item in items) {
      final torrent = _scoreItem(
        item: item,
        animeTitle: animeTitle,
        episodeNumber: episodeNumber,
        epStr: epStr,
        targetSeason: targetSeason,
        isMovieFallback: isMovieFallback,
        isMovieQuery: isMovieQuery,
      );
      if (torrent != null) validTorrents.add(torrent);
    }

    validTorrents.sort((a, b) => b.score.compareTo(a.score));
    return validTorrents;
  }

  Torrent? _scoreItem({
    required XmlElement item,
    required String animeTitle,
    required int episodeNumber,
    required String epStr,
    required int targetSeason,
    required bool isMovieFallback,
    required bool isMovieQuery,
  }) {
    double score = 100.0;

    final rawTitle = item.findElements('title').firstOrNull?.innerText ?? '';
    final tl = rawTitle.toLowerCase();
    final ql = animeTitle.toLowerCase();

    final infoHash = item.findElements('nyaa:infoHash').firstOrNull?.innerText;
    final size = item.findElements('nyaa:size').firstOrNull?.innerText ?? 'Unknown';
    final seedersStr = item.findElements('nyaa:seeders').firstOrNull?.innerText ?? '0';

    if (infoHash == null || infoHash.isEmpty) return null;

    final seedCount = int.tryParse(seedersStr) ?? 0;
    if (seedCount == 0) return null;

    if (_extractSeason(tl) == targetSeason) {
      score += 100;
    } else {
      score -= 100;
    }

    final hasFinal = ql.contains('final season');
    final torrentFinal = tl.contains('final season');
    if (hasFinal && torrentFinal) {
      score += 100;
    } else if (!hasFinal && torrentFinal) {
      score -= 100;
    }

    final torrentEp = _extractEpisode(tl);
    if (!isMovieFallback) {
      if (torrentEp != -1 && torrentEp != episodeNumber) return null;
    } else {
      if (torrentEp != -1 && torrentEp != 1) return null;
    }

    for (final tag in ['ova', 'ona', 'oad', 'special']) {
      if (!ql.contains(tag) && tl.contains(tag)) score -= 100;
    }

    if (!isMovieQuery && tl.contains('movie')) {
      score -= 100;
    } else if (isMovieQuery && (tl.contains('movie') || tl.contains('gekijouban') || tl.contains('film'))) {
      score += 50;
    }

    if (tl.contains('[batch]') || tl.contains('(batch)') || _Regex.batch.hasMatch(tl)) score -= 150;
    if (!isMovieFallback && (tl.contains('- $epStr') || tl.contains(' $epStr '))) score += 20;

    if (tl.contains('subsplease') || tl.contains('erai-raws') || tl.contains('horriblesubs')) score += 30;
    
    if (tl.contains('1080p')) {
      score += 20;
    } else if (tl.contains('720p')) {
      score += 10;
    }

    if (tl.contains('av1')) {
      score += 30;
    } else if (tl.contains('hevc') || tl.contains('x265') || tl.contains('h.265')) {
      score += 20;
    } else if (tl.contains('avc') || tl.contains('x264') || tl.contains('h.264')) {
      score += 5;
    }

    if (tl.contains('10bit') || tl.contains('10-bit')) score += 15;
    if (tl.contains('opus')) score += 10;

    if (tl.contains('web-dl') || tl.contains('webdl')) {
      score += 10;
    } else if (tl.contains('webrip')) {
      score += 5;
    }
    score += seedCount * 0.1;

    final groupMatch = _Regex.group.firstMatch(rawTitle);
    final groupName = groupMatch != null ? '[${groupMatch.group(1)}]' : 'Unknown';
    final resolution = _Regex.resolution.firstMatch(rawTitle)?.group(1) ?? 'Unknown';

    return Torrent(
      id: infoHash,
      title: rawTitle,
      releaseGroup: groupName,
      resolution: resolution,
      size: size,
      seeders: seedCount,
      magnetLink: _buildMagnet(infoHash, rawTitle),
      score: score,
    );
  }

  int _extractSeason(String title) {
    final m = _Regex.season.firstMatch(title);
    if (m != null) {
      for (int i = 1; i <= m.groupCount; i++) {
        if (m.group(i) != null) return int.tryParse(m.group(i)!) ?? 1;
      }
    }
    return 1;
  }

  int _extractEpisode(String title) {
    for (final re in [_Regex.ep1, _Regex.ep2, _Regex.ep3]) {
      final m = re.firstMatch(title);
      if (m != null && m.groupCount >= 1) return int.tryParse(m.group(1)!) ?? -1;
    }
    return -1;
  }

  String _buildMagnet(String infoHash, String title) {
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
}