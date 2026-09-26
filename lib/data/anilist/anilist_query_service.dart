import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
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

class _AnilistCacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiresAt;
  const _AnilistCacheEntry(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory TTL cache for read-only, non-personalized queries (trending,
/// seasonal/all-time popular, currently airing, search) — see API.md § 4 for
/// TTL, cap, and why watchlist/progress queries never use it.
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
    // Bounded so a long session of distinct searches can't grow this
    // unboundedly; evicts the oldest entry over the cap rather than pulling in
    // an LRU package for a handful of slots.
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

  /// Same HTTP-status and GraphQL-`errors` validation every dedicated query
  /// method gets via [_query], for callers ([AnilistTrackerService]) whose
  /// query isn't modeled as its own method here — unlike [executeRaw], a bare
  /// transport call with no validation of its own. AniList can return HTTP 200
  /// with a GraphQL `errors` array (an expired token, a mutation failure),
  /// which a plain status-code check can't catch.
  Future<Map<String, dynamic>> executeChecked(
    String query,
    Map<String, dynamic> variables,
  ) => _query(query, variables, (data) => data);

  /// The "POST → assert success → decode → select" pipeline every method below
  /// feeds its own [select] callback into, so transport/error handling lives
  /// here exactly once.
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

  /// Same contract as [_query], but checks [_AnilistCache] first and populates
  /// it after a real fetch — only for the read-only, non-personalized queries
  /// [_AnilistCache]'s doc names.
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
      // Each element of a decoded `List<dynamic>` is itself `dynamic`, so it's
      // cast before indexing to keep subsequent access statically typed
      // (`avoid_dynamic_calls`).
      String errorMessage = 'Unknown GraphQL Error';
      if (errors.isNotEmpty) {
        final first = errors[0] as Map<String, dynamic>?;
        errorMessage = first?['message'] as String? ?? errorMessage;
      }
      throw AnilistException('GraphQL Error: $errorMessage');
    }
  }

  List<Anime> _animeListFromPage(Map<String, dynamic> data) {
    final page = data['Page'] as Map<String, dynamic>?;
    final mediaList = page?['media'] as List<dynamic>? ?? const [];
    return mediaList
        .map((raw) => Anime.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<int?> _resolveViewerId() async {
    if (_viewerId != null) return _viewerId;
    if (!isLoggedIn) return null;

    try {
      _viewerId = await _query(AnilistQueries.viewerId, const {}, (data) {
        final viewer = data['Viewer'] as Map<String, dynamic>?;
        return (viewer?['id'] as num?)?.toInt();
      });
      return _viewerId;
    } catch (e, st) {
      AppLogger.e('AnilistQueryService', 'Fetch viewer id error', e, st);
      return null;
    }
  }

  Future<List<Anime>> getTrendingAnime({int page = 1, int perPage = 24}) {
    return _cachedQuery(AnilistQueries.trending, {
      'page': page,
      'perPage': perPage,
      'bannedGenres': _bannedGenres,
    }, _animeListFromPage);
  }

  Future<List<Anime>> getPopularThisSeason({int page = 1, int perPage = 24}) {
    return _cachedQuery(AnilistQueries.seasonPopular, {
      'page': page,
      'perPage': perPage,
      'season': _currentSeason,
      'seasonYear': DateTime.now().year,
      'bannedGenres': _bannedGenres,
    }, _animeListFromPage);
  }

  Future<List<Anime>> getAllTimePopular({int page = 1, int perPage = 24}) {
    return _cachedQuery(AnilistQueries.allTimePopular, {
      'page': page,
      'perPage': perPage,
      'bannedGenres': _bannedGenres,
    }, _animeListFromPage);
  }

  Future<List<Anime>> getCurrentlyAiring({int page = 1, int perPage = 50}) {
    return _cachedQuery(AnilistQueries.currentlyAiring, {
      'page': page,
      'perPage': perPage,
      'currentSeason': _currentSeason,
      'currentYear': DateTime.now().year,
      'bannedGenres': _bannedGenres,
    }, _animeListFromPage);
  }

  /// Resolves a single [Anime] by AniList id or MyAnimeList id (exactly one of
  /// [anilistId]/[idMal] should be non-null) — the browser-extension deep-link
  /// flow (ARCHITECTURE.md § 8) is the only caller, and deliberately skips
  /// `_bannedGenres` since the caller named one specific title by identity, not
  /// a browsable list. Returns null (an invalid id, or an uncross-referenced
  /// MAL id) rather than throwing, mirroring [getMediaProgress]'s "absence is a
  /// valid answer" contract.
  Future<Anime?> getAnimeByExternalId({int? anilistId, int? idMal}) {
    assert(
      (anilistId == null) != (idMal == null),
      'Provide exactly one of anilistId or idMal',
    );
    return _cachedQuery(
      AnilistQueries.mediaByExternalId,
      {'id': anilistId, 'idMal': idMal},
      (data) {
        final media = data['Media'] as Map<String, dynamic>?;
        return media != null ? Anime.fromJson(media) : null;
      },
    );
  }

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

  /// [sort] is a list of AniList `MediaListSort` values — see
  /// `WatchlistSortOption.anilistSort` (watchlist_controller.dart) for what
  /// `WatchlistScreen`'s sort dropdown maps to. Defaults to the pre-sort title
  /// order, so omitting it changes nothing.
  Future<({List<MediaListEntry> entries, bool hasNextPage})> getUserWatchlist({
    required String status,
    int page = 1,
    int perPage = 40,
    List<String> sort = const ['MEDIA_TITLE_ROMAJI', 'MEDIA_ID_DESC'],
  }) async {
    if (!isLoggedIn) throw const AnilistException('Not logged in');
    final viewerId = await _resolveViewerId();
    if (viewerId == null) {
      throw const AnilistException('Could not resolve viewer ID');
    }

    return _query(
      AnilistQueries.userWatchlistPaged,
      {
        'userId': viewerId,
        'status': status,
        'page': page,
        'perPage': perPage,
        'sort': sort,
      },
      (data) {
        final pageData = data['Page'] as Map<String, dynamic>?;
        final pageInfo = pageData?['pageInfo'] as Map<String, dynamic>?;
        final hasNextPage = pageInfo?['hasNextPage'] as bool? ?? false;
        final rawList = (pageData?['mediaList'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();

        final banned = _bannedGenres;

        // AniList exposes no `genre_not_in` filter on a user's own watchlist,
        // so the banned-genre filter runs client-side here, against the raw
        // JSON's genre list, before decoding into MediaListEntry.
        final entries = rawList
            .where((r) {
              final media = r['media'] as Map<String, dynamic>?;
              if (media == null) return true;
              final genres = media['genres'] as List<dynamic>? ?? [];
              return !genres.any(banned.contains);
            })
            .map(MediaListEntry.fromJson)
            .toList();

        return (entries: entries, hasNextPage: hasNextPage);
      },
    );
  }

  Future<int?> getMediaProgress(int mediaId) async {
    if (!isLoggedIn) return null;
    try {
      return await _query(AnilistQueries.mediaProgress, {'id': mediaId}, (
        data,
      ) {
        final media = data['Media'] as Map<String, dynamic>?;
        final entry = media?['mediaListEntry'] as Map<String, dynamic>?;
        return (entry?['progress'] as num?)?.toInt();
      });
    } catch (e, st) {
      AppLogger.e('AnilistQueryService', 'Fetch progress error', e, st);
      return null;
    }
  }

  void dispose() => _httpClient.close();
}