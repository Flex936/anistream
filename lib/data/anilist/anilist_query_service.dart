import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anistream/core/logging/app_logger.dart';
import '../../core/settings/settings_service.dart';
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

  AnilistQueryService({http.Client? client})
    : _httpClient = client ?? http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<int?> _resolveViewerId() async {
    if (_viewerId != null) return _viewerId;
    if (!isLoggedIn) return null;

    try {
      final resp = await _httpClient
          .post(
            Uri.parse(_endpoint),
            headers: _headers,
            body: jsonEncode({'query': 'query { Viewer { id } }'}),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      _viewerId = (decoded['data']?['Viewer']?['id'] as num?)?.toInt();
      return _viewerId;
    } catch (e, st) {
      AppLogger.e('AnilistQueryService', 'Fetch status error', e, st);
      return null;
    }
  }

  String get _currentSeason => switch (DateTime.now().month) {
    >= 4 && <= 6 => 'SPRING',
    >= 7 && <= 9 => 'SUMMER',
    >= 10 && <= 12 => 'FALL',
    _ => 'WINTER',
  };

  Future<http.Response> executeRaw(
    String query,
    Map<String, dynamic> variables,
  ) async {
    return await _httpClient
        .post(
          Uri.parse(_endpoint),
          headers: _headers,
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<List<Anime>> _execute(
    String query,
    Map<String, dynamic> variables,
  ) async {
    try {
      final response = await executeRaw(query, variables);
      _assertResponse(response);

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final mediaList =
          decoded['data']?['Page']?['media'] as List<dynamic>? ?? const [];

      return mediaList
          .map((raw) => Anime.fromJson(raw as Map<String, dynamic>))
          .toList();
    } on SocketException {
      throw const AnilistException(
        'No internet connection. Please check your network.',
      );
    } on TimeoutException {
      throw const AnilistException(
        'Connection timed out. AniList might be down.',
      );
    }
  }

  void _assertResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw AnilistException(
        'AniList returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded.containsKey('errors')) {
      final errors = decoded['errors'] as List<dynamic>;
      final errorMessage = errors.isNotEmpty
          ? errors[0]['message']
          : 'Unknown GraphQL Error';
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
    return _execute(_Queries.allTimePopular, {
      'page': page,
      'perPage': perPage,
    });
  }

  Future<({List<MediaListEntry> entries, bool hasNextPage})> getUserWatchlist({
    required String status,
    int page = 1,
    int perPage = 40,
  }) async {
    if (!isLoggedIn) throw const AnilistException('Not logged in');
    final viewerId = await _resolveViewerId();
    if (viewerId == null) {
      throw const AnilistException('Could not resolve viewer ID');
    }

    try {
      final response = await executeRaw(_Queries.userWatchlistPaged, {
        'userId': viewerId,
        'status': status,
        'page': page,
        'perPage': perPage,
      });
      _assertResponse(response);

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final pageData = decoded['data']?['Page'];

      final hasNextPage =
          pageData?['pageInfo']?['hasNextPage'] as bool? ?? false;
      final rawList = pageData?['mediaList'] as List<dynamic>? ?? const [];

      final entries = rawList
          .map((r) => MediaListEntry.fromJson(r as Map<String, dynamic>))
          .toList();
      return (entries: entries, hasNextPage: hasNextPage);
    } on SocketException {
      throw const AnilistException(
        'No internet connection. Please check your network.',
      );
    } on TimeoutException {
      throw const AnilistException(
        'Connection timed out. AniList might be down.',
      );
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
    // ── Upgraded to SharedPreferencesAsync ──
    final prefs = SharedPreferencesAsync();
    final filterEcchi =
        await prefs.getBool(SettingsService.kFilterEcchi) ?? true;
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

  Future<int?> getMediaProgress(int mediaId) async {
    if (!isLoggedIn) return null;
    try {
      final response = await executeRaw(
        'query (\$id: Int) { Media(id: \$id) { mediaListEntry { progress } } }',
        {'id': mediaId},
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      return data['data']?['Media']?['mediaListEntry']?['progress'] as int?;
    } catch (e, st) {
      AppLogger.e('AnilistQueryService', 'Fetch status error', e, st);
      return null;
    }
  }

  void dispose() => _httpClient.close();
}

abstract final class _Fragments {
  static const String mediaCore = r'''
    id
    idMal
    title { romaji english }
    synonyms
    coverImage { extraLarge large }
    bannerImage
    description
    episodes
    status
    format
    averageScore
    nextAiringEpisode { episode airingAt }
  ''';
}

abstract final class _Queries {
  static const String trending =
      '''
    query GetTrendingAnime(\$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) { media(sort: TRENDING_DESC, type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED) { ${_Fragments.mediaCore} } }
    }''';

  static const String seasonPopular =
      '''
    query GetSeasonPopular(\$page: Int, \$perPage: Int, \$season: MediaSeason, \$seasonYear: Int) {
      Page(page: \$page, perPage: \$perPage) { media(season: \$season, seasonYear: \$seasonYear, sort: POPULARITY_DESC, type: ANIME, isAdult: false) { ${_Fragments.mediaCore} } }
    }''';

  static const String allTimePopular =
      '''
    query GetAllTimePopular(\$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) { media(sort: POPULARITY_DESC, type: ANIME, isAdult: false) { ${_Fragments.mediaCore} } }
    }''';

  static const String search =
      '''
    query (\$search: String, \$bannedGenres: [String], \$minScore: Int, \$status: MediaStatus, \$seasonYear: Int) {
      Page(page: 1, perPage: 15) { media(search: \$search, type: ANIME, sort: SEARCH_MATCH, isAdult: false, genre_not_in: \$bannedGenres, status_not: NOT_YET_RELEASED, averageScore_greater: \$minScore, status: \$status, seasonYear: \$seasonYear) { ${_Fragments.mediaCore} } }
    }''';

  static const String userWatchlistPaged =
      '''
    query (\$userId: Int, \$status: MediaListStatus, \$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) {
        pageInfo { hasNextPage }
        mediaList(userId: \$userId, type: ANIME, status: \$status, sort: [MEDIA_TITLE_ROMAJI, MEDIA_ID_DESC]) {
          progress
          media { ${_Fragments.mediaCore} genres }
        }
      }
    }''';

  static const String currentlyAiring = r'''
    query GetCurrentlyAiring($page: Int, $perPage: Int, $currentSeason: MediaSeason, $currentYear: Int) {
      Page(page: $page, perPage: $perPage) { media(type: ANIME, season: $currentSeason, seasonYear: $currentYear, sort: TRENDING_DESC, countryOfOrigin: "JP", isAdult: false, format_not_in: [SPECIAL, OVA, ONA, MOVIE]) { id idMal title { romaji english } synonyms coverImage { extraLarge large } bannerImage description episodes status nextAiringEpisode { episode airingAt } } }
    }''';
}
