import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/anime.dart';
import 'models/media_list.dart';

class AnilistException implements Exception {
  final String message;
  final int? statusCode;
  const AnilistException(this.message, {this.statusCode});
  @override
  String toString() => 'AnilistException($statusCode): $message';
}

class AnilistQueryService {
  static const String _endpoint = 'https://graphql.anilist.co';

  static String? _token;
  static int? _viewerId;

  static void setToken(String token) {
    _token = token;
    _viewerId = null;
  }

  static void clearToken() {
    _token = null;
    _viewerId = null;
  }

  static bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  final http.Client _httpClient;

  AnilistQueryService({http.Client? client}) : _httpClient = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<int?> _resolveViewerId() async {
    if (_viewerId != null) return _viewerId;
    if (!isLoggedIn) return null;

    try {
      final resp = await _httpClient.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: jsonEncode({'query': 'query { Viewer { id } }'}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      _viewerId = (decoded['data']?['Viewer']?['id'] as num?)?.toInt();
      return _viewerId;
    } catch (_) {
      return null;
    }
  }

  String get _currentSeason {
    final month = DateTime.now().month;
    if (month >= 4 && month <= 6) return 'SPRING';
    if (month >= 7 && month <= 9) return 'SUMMER';
    if (month >= 10 && month <= 12) return 'FALL';
    return 'WINTER';
  }

  Future<List<Anime>> _execute(String query, Map<String, dynamic> variables) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: jsonEncode({'query': query, 'variables': variables}),
      ).timeout(const Duration(seconds: 15));

      _assertResponse(response);

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final mediaList = decoded['data']?['Page']?['media'] as List<dynamic>? ?? const [];

      return mediaList.map((raw) => Anime.fromJson(raw as Map<String, dynamic>)).toList();
    } on SocketException {
      throw const AnilistException('No internet connection. Please check your network.');
    } on TimeoutException {
      throw const AnilistException('Connection timed out. AniList might be down.');
    }
  }

  void _assertResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw AnilistException('AniList returned HTTP ${response.statusCode}', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded.containsKey('errors')) {
      final errors = decoded['errors'] as List<dynamic>;
      final errorMessage = errors.isNotEmpty ? errors[0]['message'] : 'Unknown GraphQL Error';
      throw AnilistException('GraphQL Error: $errorMessage');
    }
  }

  Future<List<Anime>> getTrendingAnime({int page = 1, int perPage = 24}) {
    return _execute(_Queries.trending, {'page': page, 'perPage': perPage});
  }

  Future<List<Anime>> getPopularThisSeason({int page = 1, int perPage = 24}) {
    return _execute(_Queries.seasonPopular, {
      'page': page,
      'perPage': perPage,
      'season': _currentSeason,
      'seasonYear': DateTime.now().year,
    });
  }

  Future<List<Anime>> getAllTimePopular({int page = 1, int perPage = 24}) {
    return _execute(_Queries.allTimePopular, {'page': page, 'perPage': perPage});
  }

  Future<List<MediaList>> getUserWatchlist() async {
    if (!isLoggedIn) throw const AnilistException('Not logged in');
    final viewerId = await _resolveViewerId();
    if (viewerId == null) throw const AnilistException('Could not resolve viewer ID');

    try {
      final response = await _httpClient.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: jsonEncode({
          'query': _Queries.userWatchlist,
          'variables': {'userId': viewerId},
        }),
      ).timeout(const Duration(seconds: 15));

      _assertResponse(response);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final lists = decoded['data']?['MediaListCollection']?['lists'] as List<dynamic>? ?? const [];
      
      return lists.map((r) => MediaList.fromJson(r as Map<String, dynamic>)).toList();
    } on SocketException {
      throw const AnilistException('No internet connection. Please check your network.');
    } on TimeoutException {
      throw const AnilistException('Connection timed out. AniList might be down.');
    }
  }

  Future<List<Anime>> getCurrentlyAiring({int page = 1, int perPage = 50}) {
    return _execute(_Queries.currentlyAiring, {
      'page': page,
      'perPage': perPage,
      'currentSeason': _currentSeason,
      'currentYear': DateTime.now().year,
    });
  }

  Future<List<Anime>> searchAnime(
    String query, {
    int? minScore,
    String? status,
    int? year,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final filterEcchi = prefs.getBool('filter_ecchi') ?? true;
    final bannedGenres = filterEcchi ? ['Hentai', 'Ecchi'] : ['Hentai'];

    final variables = <String, dynamic>{
      'search': query,
      'bannedGenres': bannedGenres,
    };

    if (minScore != null && minScore > 0) variables['minScore'] = minScore;
    if (status != null && status != 'ANY') variables['status'] = status;
    if (year != null) variables['seasonYear'] = year;

    return _execute(_Queries.search, variables);
  }

  void dispose() => _httpClient.close();
}

// ── Segregated GraphQL Strings ──
abstract final class _Queries {
  static const String trending = r'''
    query GetTrendingAnime($page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) { media(sort: TRENDING_DESC, type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED) { id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt } } }
    }''';

  static const String seasonPopular = r'''
    query GetSeasonPopular($page: Int, $perPage: Int, $season: MediaSeason, $seasonYear: Int) {
      Page(page: $page, perPage: $perPage) { media(season: $season, seasonYear: $seasonYear, sort: POPULARITY_DESC, type: ANIME, isAdult: false) { id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt } } }
    }''';

  static const String allTimePopular = r'''
    query GetAllTimePopular($page: Int, $perPage: Int) {
      Page(page: $page, perPage: $perPage) { media(sort: POPULARITY_DESC, type: ANIME, isAdult: false) { id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt } } }
    }''';

  static const String userWatchlist = r'''
    query ($userId: Int) {
      MediaListCollection(userId: $userId, type: ANIME, status_in: [CURRENT, PLANNING, COMPLETED]) { lists { name status entries { progress media { id title { romaji english } coverImage { extraLarge large } bannerImage genres averageScore episodes status description nextAiringEpisode { episode airingAt } } } } }
    }''';

  static const String currentlyAiring = r'''
    query GetCurrentlyAiring($page: Int, $perPage: Int, $currentSeason: MediaSeason, $currentYear: Int) {
      Page(page: $page, perPage: $perPage) { media(type: ANIME, season: $currentSeason, seasonYear: $currentYear, sort: TRENDING_DESC, countryOfOrigin: "JP", isAdult: false, format_not_in: [SPECIAL, OVA, ONA, MOVIE]) { id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status nextAiringEpisode { episode airingAt } } }
    }''';

  static const String search = r'''
    query ($search: String, $bannedGenres: [String], $minScore: Int, $status: MediaStatus, $seasonYear: Int) {
      Page(page: 1, perPage: 15) { media(search: $search, type: ANIME, sort: SEARCH_MATCH, isAdult: false, genre_not_in: $bannedGenres, status_not: NOT_YET_RELEASED, averageScore_greater: $minScore, status: $status, seasonYear: $seasonYear) { id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt } } }
    }''';
}