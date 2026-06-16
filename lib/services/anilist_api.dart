import 'dart:convert';
import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
//  Data models
// ════════════════════════════════════════════════════════════════════════════

class NextAiringEpisode {
  final int episode;
  const NextAiringEpisode({required this.episode});

  factory NextAiringEpisode.fromJson(Map<String, dynamic> json) =>
      NextAiringEpisode(episode: json['episode'] as int);
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
  const AnimeCoverImage({this.extraLarge});

  factory AnimeCoverImage.fromJson(Map<String, dynamic> json) =>
      AnimeCoverImage(extraLarge: json['extraLarge'] as String?);
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
      id: json['id'] as int,
      title: rawTitle != null
          ? AnimeTitle.fromJson(rawTitle)
          : const AnimeTitle(),
      coverImage: rawCover != null ? AnimeCoverImage.fromJson(rawCover) : null,
      bannerImage: json['bannerImage'] as String?,
      description: json['description'] as String?,
      episodes: json['episodes'] as int?,
      status: json['status'] as String?,
      averageScore: json['averageScore'] as int?,
      nextAiringEpisode: rawNextEp != null
          ? NextAiringEpisode.fromJson(rawNextEp)
          : null,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Service
// ════════════════════════════════════════════════════════════════════════════

class AnilistApiService {
  static const String _endpoint = 'https://graphql.anilist.co';
  static const String _trendingQuery = r'''
query GetTrendingAnime($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: TRENDING_DESC, type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED) {
      id
      title {
        romaji
        english
      }
      coverImage {
        extraLarge
      }
      bannerImage
      description
      episodes
      status
      averageScore
      nextAiringEpisode {
        episode
      }
    }
  }
}''';

  final http.Client _httpClient;

  AnilistApiService({http.Client? client})
    : _httpClient = client ?? http.Client();

  Future<List<Anime>> getTrendingAnime({int page = 1, int perPage = 24}) async {
    final response = await _httpClient.post(
      Uri.parse(_endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'query': _trendingQuery,
        'variables': {'page': page, 'perPage': perPage},
      }),
    );

    if (response.statusCode != 200) {
      throw AnilistException(
        'AniList returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;
    final page0 = data?['Page'] as Map<String, dynamic>?;
    final mediaList = page0?['media'] as List<dynamic>? ?? const [];

    return mediaList
        .map((raw) => Anime.fromJson(raw as Map<String, dynamic>))
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
            id
            title { romaji english }
            coverImage { extraLarge }
            bannerImage
            description
            episodes
            status
            averageScore
            nextAiringEpisode { episode }
          }
        }
      }''';

    final bannedGenres = filterEcchi ? ['Hentai', 'Ecchi'] : ['Hentai'];

    final response = await _httpClient.post(
      Uri.parse(_endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'query': searchQuery,
        'variables': {'search': query, 'bannedGenres': bannedGenres},
      }),
    );

    if (response.statusCode != 200) {
      throw AnilistException('AniList returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;
    final page0 = data?['Page'] as Map<String, dynamic>?;
    final mediaList = page0?['media'] as List<dynamic>? ?? const [];

    return mediaList
        .map((raw) => Anime.fromJson(raw as Map<String, dynamic>))
        .toList();
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
