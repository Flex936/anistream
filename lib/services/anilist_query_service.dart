import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Data models
// ════════════════════════════════════════════════════════════════════════════

class NextAiringEpisode {
  final int episode;
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

  String get display => romaji ?? english ?? 'Unknown Title';
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
  final List<String>? genres; 
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
    this.genres,
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
      genres: (json['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      nextAiringEpisode: rawNextEp != null ? NextAiringEpisode.fromJson(rawNextEp) : null,
    );
  }
}

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
  final String status;
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

  // ── GraphQL Queries ──

  static const String _trendingQuery = r'''
query GetTrendingAnime($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: TRENDING_DESC, type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED) {
      id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt }
    }
  }
}''';

  static const String _seasonPopularQuery = r'''
query GetSeasonPopular($page: Int, $perPage: Int, $season: MediaSeason, $seasonYear: Int) {
  Page(page: $page, perPage: $perPage) {
    media(season: $season, seasonYear: $seasonYear, sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
      id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt }
    }
  }
}''';

  static const String _allTimePopularQuery = r'''
query GetAllTimePopular($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
      id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt }
    }
  }
}''';

  // ── FIXED: Added COMPLETED to the status_in array ──
  static const String _userWatchList = r'''
query ($userId: Int) {
  MediaListCollection(userId: $userId, type: ANIME, status_in: [CURRENT, PLANNING, COMPLETED]) {
    lists {
      name status entries { progress media { id title { romaji english } coverImage { extraLarge large } bannerImage genres averageScore episodes status description nextAiringEpisode { episode airingAt } } }
    }
  }
}''';

  static const String _currentlyAiringQuery = r'''
query GetCurrentlyAiring($page: Int, $perPage: Int, $currentSeason: MediaSeason, $currentYear: Int) {
  Page(page: $page, perPage: $perPage) {
    media(type: ANIME, season: $currentSeason, seasonYear: $currentYear, sort: TRENDING_DESC, countryOfOrigin: "JP", isAdult: false, format_not_in: [SPECIAL, OVA, ONA, MOVIE]) {
      id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status nextAiringEpisode { episode airingAt }
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

  Future<List<Anime>> _execute(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await _httpClient.post(
      Uri.parse(_endpoint),
      headers: _headers,
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

  Future<List<Anime>> getCurrentlyAiring({int page = 1, int perPage = 50}) {
    return _execute(_currentlyAiringQuery, {
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
    const searchQuery = r'''
      query ($search: String, $bannedGenres: [String], $minScore: Int, $status: MediaStatus, $seasonYear: Int) {
        Page(page: 1, perPage: 15) {
          media(
            search: $search, 
            type: ANIME, 
            sort: SEARCH_MATCH, 
            isAdult: false, 
            genre_not_in: $bannedGenres, 
            status_not: NOT_YET_RELEASED,
            averageScore_greater: $minScore,
            status: $status,
            seasonYear: $seasonYear
          ) {
            id title { romaji english } coverImage { extraLarge large } bannerImage description episodes status averageScore nextAiringEpisode { episode airingAt }
          }
        }
      }''';
    
    // Wire up the NSFW filter dynamically from user settings
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

    return _execute(searchQuery, variables);
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
