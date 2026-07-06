import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anistream/core/logging/app_logger.dart';
import '../../core/settings/settings_service.dart';
import 'anilist_queries.dart';
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

  String get _currentSeason => switch (DateTime.now().month) {
    >= 4 && <= 6 => 'SPRING',
    >= 7 && <= 9 => 'SUMMER',
    >= 10 && <= 12 => 'FALL',
    _ => 'WINTER',
  };

  /// Raw POST — used directly by callers (e.g. AnilistTrackerService) that
  /// need the http.Response itself rather than a parsed model.
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

  /// Generic "POST → assert success → decode → select" pipeline. Every
  /// method below just supplies a [select] callback for the slice of the
  /// decoded body it cares about; the transport/error handling lives here
  /// exactly once instead of being copy-pasted per method.
  Future<T> _query<T>(
    String query,
    Map<String, dynamic> variables,
    T Function(Map<String, dynamic> data) select,
  ) async {
    try {
      final response = await executeRaw(query, variables);
      _assertResponse(response);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return select(decoded['data'] as Map<String, dynamic>? ?? const {});
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

  List<Anime> _animeListFromPage(Map<String, dynamic> data) {
    final mediaList = data['Page']?['media'] as List<dynamic>? ?? const [];
    return mediaList
        .map((raw) => Anime.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<int?> _resolveViewerId() async {
    if (_viewerId != null) return _viewerId;
    if (!isLoggedIn) return null;

    try {
      _viewerId = await _query(
        AnilistQueries.viewerId,
        const {},
        (data) => (data['Viewer']?['id'] as num?)?.toInt(),
      );
      return _viewerId;
    } catch (e, st) {
      AppLogger.e('AnilistQueryService', 'Fetch viewer id error', e, st);
      return null;
    }
  }

  Future<List<Anime>> getTrendingAnime({int page = 1, int perPage = 24}) =>
      _query(AnilistQueries.trending, {
        'page': page,
        'perPage': perPage,
      }, _animeListFromPage);

  Future<List<Anime>> getPopularThisSeason({int page = 1, int perPage = 24}) =>
      _query(AnilistQueries.seasonPopular, {
        'page': page,
        'perPage': perPage,
        'season': _currentSeason,
        'seasonYear': DateTime.now().year,
      }, _animeListFromPage);

  Future<List<Anime>> getAllTimePopular({int page = 1, int perPage = 24}) =>
      _query(AnilistQueries.allTimePopular, {
        'page': page,
        'perPage': perPage,
      }, _animeListFromPage);

  Future<List<Anime>> getCurrentlyAiring({int page = 1, int perPage = 50}) =>
      _query(AnilistQueries.currentlyAiring, {
        'page': page,
        'perPage': perPage,
        'currentSeason': _currentSeason,
        'currentYear': DateTime.now().year,
      }, _animeListFromPage);

  Future<List<Anime>> searchAnime(
    String query, {
    int? minScore,
    String? status,
    int? year,
  }) async {
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

    return _query(AnilistQueries.search, variables, _animeListFromPage);
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

    return _query(
      AnilistQueries.userWatchlistPaged,
      {'userId': viewerId, 'status': status, 'page': page, 'perPage': perPage},
      (data) {
        final pageData = data['Page'];
        final hasNextPage =
            pageData?['pageInfo']?['hasNextPage'] as bool? ?? false;
        final rawList = pageData?['mediaList'] as List<dynamic>? ?? const [];
        final entries = rawList
            .map((r) => MediaListEntry.fromJson(r as Map<String, dynamic>))
            .toList();
        return (entries: entries, hasNextPage: hasNextPage);
      },
    );
  }

  Future<int?> getMediaProgress(int mediaId) async {
    if (!isLoggedIn) return null;
    try {
      return await _query(
        AnilistQueries.mediaProgress,
        {'id': mediaId},
        (data) =>
            (data['Media']?['mediaListEntry']?['progress'] as num?)?.toInt(),
      );
    } catch (e, st) {
      AppLogger.e('AnilistQueryService', 'Fetch progress error', e, st);
      return null;
    }
  }

  void dispose() => _httpClient.close();
}
