import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:anistream/core/logging/app_logger.dart';
import 'anilist_queries.dart';
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

class _AnilistCacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiresAt;
  const _AnilistCacheEntry(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Tiny in-memory TTL cache for read-only, non-personalized AniList
/// queries (trending / seasonal / all-time popular / currently airing /
/// search). Keyed by query string + JSON-encoded variables, so distinct
/// filter combinations (different search term, different minScore, etc.)
/// get distinct entries automatically.
///
/// Fixes: `NavigationController.goHome()` builds a brand-new `HomeScreen`
/// (and a brand-new `AnilistQueryService`) every time the user navigates
/// Home → Details → Home, so without this, the three home carousels
/// refetched from the network on every single trip back to Home.
///
/// Deliberately NOT used for `getUserWatchlist` or `getMediaProgress` —
/// those need to reflect the viewer's live, current state, and a stale
/// cache hit right after finishing an episode would show the wrong
/// "up next" number or watchlist progress bar.
abstract final class _AnilistCache {
  static final Map<String, _AnilistCacheEntry> _entries = {};
  static const Duration _ttl = Duration(minutes: 2);
  static const int _maxEntries = 40;

  static String _keyFor(String query, Map<String, dynamic> variables) =>
      '$query::${jsonEncode(variables)}';

  static Map<String, dynamic>? get(
    String query,
    Map<String, dynamic> variables,
  ) {
    final key = _keyFor(query, variables);
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _entries.remove(key);
      return null;
    }
    return entry.data;
  }

  static void set(
    String query,
    Map<String, dynamic> variables,
    Map<String, dynamic> data,
  ) {
    // ── Simple bound so a long session of distinct searches can't grow
    // this unboundedly — evict the oldest entry once over the cap rather
    // than pull in a full LRU package for what's normally a handful of
    // slots (3 home carousels + whatever the user has searched). ──
    if (_entries.length >= _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[_keyFor(query, variables)] = _AnilistCacheEntry(
      data,
      DateTime.now().add(_ttl),
    );
  }
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

  /// Single source of truth for retrieving banned genres based on user settings.
  List<String> get _bannedGenres {
    final filterEcchi = SettingsCache.current.filterEcchi;
    return filterEcchi ? ['Hentai', 'Ecchi'] : ['Hentai'];
  }

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

  /// Same contract as [_query], but checks [_AnilistCache] first and
  /// populates it after a real network fetch. Only used by the read-only,
  /// non-personalized queries listed on [_AnilistCache]'s doc comment —
  /// see there for why the rest of this service deliberately doesn't use
  /// this wrapper.
  Future<T> _cachedQuery<T>(
    String query,
    Map<String, dynamic> variables,
    T Function(Map<String, dynamic> data) select,
  ) {
    final cached = _AnilistCache.get(query, variables);
    if (cached != null) {
      return Future.value(select(cached));
    }
    return _query(query, variables, (data) {
      _AnilistCache.set(query, variables, data);
      return select(data);
    });
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
      _cachedQuery(AnilistQueries.trending, {
        'page': page,
        'perPage': perPage,
        'bannedGenres': _bannedGenres,
      }, _animeListFromPage);

  Future<List<Anime>> getPopularThisSeason({int page = 1, int perPage = 24}) =>
      _cachedQuery(AnilistQueries.seasonPopular, {
        'page': page,
        'perPage': perPage,
        'season': _currentSeason,
        'seasonYear': DateTime.now().year,
        'bannedGenres': _bannedGenres,
      }, _animeListFromPage);

  Future<List<Anime>> getAllTimePopular({int page = 1, int perPage = 24}) =>
      _cachedQuery(AnilistQueries.allTimePopular, {
        'page': page,
        'perPage': perPage,
        'bannedGenres': _bannedGenres,
      }, _animeListFromPage);

  Future<List<Anime>> getCurrentlyAiring({int page = 1, int perPage = 50}) =>
      _cachedQuery(AnilistQueries.currentlyAiring, {
        'page': page,
        'perPage': perPage,
        'currentSeason': _currentSeason,
        'currentYear': DateTime.now().year,
        'bannedGenres': _bannedGenres,
      }, _animeListFromPage);

  Future<List<Anime>> searchAnime(
    String query, {
    int? minScore,
    String? status,
    int? year,
  }) async {
    final variables = <String, dynamic>{
      'search': query,
      'bannedGenres': _bannedGenres,
    };

    if (minScore != null && minScore > 0) variables['minScore'] = minScore;
    if (status != null && status != 'ANY') variables['status'] = status;
    if (year != null) variables['seasonYear'] = year;

    return _cachedQuery(AnilistQueries.search, variables, _animeListFromPage);
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

        final banned = _bannedGenres;

        // ── Since AniList does not natively allow filtering user watchlists
        // by `genre_not_in`, we extract the genres out of the raw JSON map
        // before converting them so we don't depend on missing parameters
        // inside the Anime/MediaListEntry models. ──
        final entries = rawList
            .where((r) {
              final media = r['media'] as Map<String, dynamic>?;
              if (media == null) return true;
              final genres = media['genres'] as List<dynamic>? ?? [];
              return !genres.any((g) => banned.contains(g));
            })
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
