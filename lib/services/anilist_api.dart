// lib/services/anilist_api.dart
//
// AniList GraphQL client — data models + service.
//
// Auth state (_token, _viewerId) is stored in static fields so every
// instance (HomeScreen, SearchResultsScreen, WatchlistScreen…) shares the
// same session without needing a singleton or dependency injection.
// Call [AnilistApiService.setToken] / [AnilistApiService.clearToken] from
// AppShell after a login/logout event.
import 'dart:convert';
import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
//  Data models
// ════════════════════════════════════════════════════════════════════════════

class NextAiringEpisode {
  final int episode;
  // Unix timestamp — consumed by ScheduledView for countdown timers.
  final int airingAt;

  const NextAiringEpisode({required this.episode, required this.airingAt});

  factory NextAiringEpisode.fromJson(Map<String, dynamic> json) =>
      NextAiringEpisode(
        episode: (json['episode'] as num?)?.toInt() ?? 0,
        airingAt: (json['airingAt'] as num?)?.toInt() ?? 0,
      );
}

class AnimeTitle {
  final String? romaji;
  final String? english;

  const AnimeTitle({this.romaji, this.english});

  factory AnimeTitle.fromJson(Map<String, dynamic> json) => AnimeTitle(
    romaji: json['romaji'] as String?,
    english: json['english'] as String?,
  );

  // Prefers English title for display if available, falling back to Romaji
  String get display => english ?? romaji ?? 'Unknown Title';
}

class AnimeCoverImage {
  final String? extraLarge;
  final String? large;

  const AnimeCoverImage({this.extraLarge, this.large});

  factory AnimeCoverImage.fromJson(Map<String, dynamic> json) =>
      AnimeCoverImage(
        extraLarge: json['extraLarge'] as String?,
        large: json['large'] as String?,
      );

  /// Best available cover URL — prefers extraLarge, falls back to large.
  String? get display => extraLarge ?? large;
}

class Anime {
  final int id;
  final AnimeTitle title;
  final AnimeCoverImage? coverImage;
  final String? bannerImage;
  final String? description;
  final int? episodes;
  final String? status;
  final int? averageScore;
  final NextAiringEpisode? nextAiringEpisode;

  const Anime({
    required this.id,
    required this.title,
    this.coverImage,
    this.bannerImage,
    this.description,
    this.episodes,
    this.status,
    this.averageScore,
    this.nextAiringEpisode,
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    final rawTitle = json['title'] as Map<String, dynamic>?;
    final rawCover = json['coverImage'] as Map<String, dynamic>?;
    final rawNextEp = json['nextAiringEpisode'] as Map<String, dynamic>?;

    return Anime(
      id: (json['id'] as num).toInt(),
      title: rawTitle != null
          ? AnimeTitle.fromJson(rawTitle)
          : const AnimeTitle(),
      coverImage: rawCover != null ? AnimeCoverImage.fromJson(rawCover) : null,
      bannerImage: json['bannerImage'] as String?,
      description: json['description'] as String?,
      episodes: (json['episodes'] as num?)?.toInt(),
      status: json['status'] as String?,
      averageScore: (json['averageScore'] as num?)?.toInt(),
      nextAiringEpisode: rawNextEp != null
          ? NextAiringEpisode.fromJson(rawNextEp)
          : null,
    );
  }
}

// ── Watchlist models ──────────────────────────────────────────────────────────

class MediaListEntry {
  final int progress;
  final Anime media;

  const MediaListEntry({required this.progress, required this.media});

  factory MediaListEntry.fromJson(Map<String, dynamic> json) => MediaListEntry(
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    media: Anime.fromJson(json['media'] as Map<String, dynamic>),
  );
}

class MediaList {
  final String name;
  final String status; // 'CURRENT' | 'PLANNING'
  final List<MediaListEntry> entries;

  const MediaList({
    required this.name,
    required this.status,
    required this.entries,
  });

  factory MediaList.fromJson(Map<String, dynamic> json) => MediaList(
    name: json['name'] as String? ?? '',
    status: json['status'] as String? ?? '',
    entries: (json['entries'] as List<dynamic>? ?? [])
        .map((e) => MediaListEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  Service
// ════════════════════════════════════════════════════════════════════════════

class AnilistApiService {
  static const String _endpoint = 'https://graphql.anilist.co';

  // ── Shared auth state ─────────────────────────────────────────────────────
  static String? _token;
  static int? _viewerId; // cached after first Viewer query

  static void setToken(String token) {
    _token = token;
    _viewerId = null; // reset cache — new token = potentially different user
  }

  static void clearToken() {
    _token = null;
    _viewerId = null;
  }

  static bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  // ── Instance ──────────────────────────────────────────────────────────────

  final http.Client _httpClient;

  AnilistApiService({http.Client? client})
    : _httpClient = client ?? http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // ── Viewer ID resolution ─────────────────────────────────────────────────

  Future<int?> _resolveViewerId() async {
    if (_viewerId != null) return _viewerId;
    if (!isLoggedIn) return null;

    const gql = 'query { Viewer { id } }';
    final resp = await _httpClient.post(
      Uri.parse(_endpoint),
      headers: _headers,
      body: jsonEncode({'query': gql}),
    );
    if (resp.statusCode != 200) return null;

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final id = (decoded['data']?['Viewer']?['id'] as num?)?.toInt();
    _viewerId = id;
    return id;
  }

  // ── GraphQL Queries (Updated with large coverImage and airingAt fields) ──

  static const String _trendingQuery = r'''
query GetTrendingAnime($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: TRENDING_DESC, type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED) {
      id
      title { romaji english }
      coverImage { extraLarge large }
      bannerImage
      description
      episodes
      status
      averageScore
      nextAiringEpisode { episode airingAt }
    }
  }
}''';

  static const String _seasonPopularQuery = r'''
query GetSeasonPopular($page: Int, $perPage: Int, $season: MediaSeason, $seasonYear: Int) {
  Page(page: $page, perPage: $perPage) {
    media(season: $season, seasonYear: $seasonYear, sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
      id
      title { romaji english }
      coverImage { extraLarge large }
      bannerImage
      description
      episodes
      status
      averageScore
      nextAiringEpisode { episode airingAt }
    }
  }
}''';

  static const String _allTimePopularQuery = r'''
query GetAllTimePopular($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
      id
      title { romaji english }
      coverImage { extraLarge large }
      bannerImage
      description
      episodes
      status
      averageScore
      nextAiringEpisode { episode airingAt }
    }
  }
}''';

  static const String _userWatchList = r'''
query ($userId: Int) {
  MediaListCollection(userId: $userId, type: ANIME, status_in: [CURRENT, PLANNING]) {
    lists {
      name
      status
      entries {
        progress
        media {
          id
          title { romaji english }
          coverImage { extraLarge large }
          episodes
          status
          description
          nextAiringEpisode { episode airingAt }
        }
      }
    }
  }
}''';

  String get _currentSeason {
    final month = DateTime.now().month;
    if (month >= 4 && month <= 6) return 'SPRING';
    if (month >= 7 && month <= 9) return 'SUMMER';
    if (month >= 10 && month <= 12) return 'FALL';
    return 'WINTER';
  }

  // ── Core Executive Helpers ────────────────────────────────────────────────

  /// Internal helper for page-based queries that return a list of Anime objects.
  Future<List<Anime>> _execute(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await _httpClient.post(
      Uri.parse(_endpoint),
      headers:
          _headers, // Fixed: Use dynamic headers to pass authentication token
      body: jsonEncode({'query': query, 'variables': variables}),
    );

    _assertResponse(response);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;
    final pageData = data?['Page'] as Map<String, dynamic>?;
    final mediaList = pageData?['media'] as List<dynamic>? ?? const [];

    return mediaList
        .map((raw) => Anime.fromJson(raw as Map<String, dynamic>))
        .toList();
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

  // ── Public API Methods ────────────────────────────────────────────────────

  Future<List<Anime>> getTrendingAnime({int page = 1, int perPage = 24}) {
    return _execute(_trendingQuery, {'page': page, 'perPage': perPage});
  }

  Future<List<Anime>> getPopularThisSeason({int page = 1, int perPage = 24}) {
    return _execute(_seasonPopularQuery, {
      'page': page,
      'perPage': perPage,
      'season': _currentSeason,
      'seasonYear': DateTime.now().year,
    });
  }

  Future<List<Anime>> getAllTimePopular({int page = 1, int perPage = 24}) {
    return _execute(_allTimePopularQuery, {'page': page, 'perPage': perPage});
  }

  /// Fetches the current user's CURRENT + PLANNING watchlist collections.
  Future<List<MediaList>> getUserWatchlist() async {
    if (!isLoggedIn) throw const AnilistException('Not logged in');

    final viewerId = await _resolveViewerId();
    if (viewerId == null) {
      throw const AnilistException('Could not resolve viewer ID');
    }

    final response = await _httpClient.post(
      Uri.parse(_endpoint),
      headers: _headers,
      body: jsonEncode({
        'query': _userWatchList,
        'variables': {'userId': viewerId},
      }),
    );

    _assertResponse(response);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final lists =
        decoded['data']?['MediaListCollection']?['lists'] as List<dynamic>? ??
        const [];

    return lists
        .map((r) => MediaList.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Anime>> searchAnime(
    String query, {
    bool filterEcchi = true,
  }) async {
    const searchQuery = r'''
      query ($search: String, $bannedGenres: [String]) {
        Page(page: 1, perPage: 15) {
          media(search: $search, type: ANIME, sort: SEARCH_MATCH, isAdult: false, genre_not_in: $bannedGenres, status_not: NOT_YET_RELEASED) {
            id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt }
          }
        }
      }''';
    final bannedGenres = filterEcchi ? ['Hentai', 'Ecchi'] : ['Hentai'];
    return _execute(searchQuery, {
      'search': query,
      'bannedGenres': bannedGenres,
    });
  }

  void dispose() => _httpClient.close();
}

class AnilistException implements Exception {
  final String message;
  final int? statusCode;
  const AnilistException(this.message, {this.statusCode});
  @override
  String toString() => 'AnilistException($statusCode): $message';
}
