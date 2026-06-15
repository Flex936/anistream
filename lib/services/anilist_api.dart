import 'dart:convert';

import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
//  Data models
// ════════════════════════════════════════════════════════════════════════════

/// Anime title in multiple languages, mirroring [AnimeTitle] in types.go.
class AnimeTitle {
  final String? romaji;
  final String? english;

  const AnimeTitle({this.romaji, this.english});

  factory AnimeTitle.fromJson(Map<String, dynamic> json) => AnimeTitle(
    romaji: json['romaji'] as String?,
    english: json['english'] as String?,
  );

  /// Returns the best available title, preferring Romaji over English.
  String get display => romaji ?? english ?? 'Unknown Title';
}

/// Poster image URLs at various resolutions.
class AnimeCoverImage {
  final String? extraLarge;

  const AnimeCoverImage({this.extraLarge});

  factory AnimeCoverImage.fromJson(Map<String, dynamic> json) =>
      AnimeCoverImage(extraLarge: json['extraLarge'] as String?);
}

/// A single AniList media entry, nullable-safe.
///
/// Fields that the API may omit (episodes, averageScore, etc.) are typed
/// as nullable so [fromJson] never throws on partial responses.
class Anime {
  final int id;
  final AnimeTitle title;
  final AnimeCoverImage? coverImage;
  final String? bannerImage;
  final String? description;
  final int? episodes;
  final String? status;
  final int? averageScore;

  const Anime({
    required this.id,
    required this.title,
    this.coverImage,
    this.bannerImage,
    this.description,
    this.episodes,
    this.status,
    this.averageScore,
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    // Defensive casts — the API may return null for any nested object.
    final rawTitle = json['title'] as Map<String, dynamic>?;
    final rawCover = json['coverImage'] as Map<String, dynamic>?;

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
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Service
// ════════════════════════════════════════════════════════════════════════════

/// Communicates with the AniList GraphQL endpoint.
///
/// ```dart
/// final api = AnilistApiService();
/// final trending = await api.getTrendingAnime();
/// api.dispose(); // release the connection pool when done
/// ```
class AnilistApiService {
  static const String _endpoint = 'https://graphql.anilist.co';

  /// Exact query requested in the migration spec.
  static const String _trendingQuery = r'''
query GetTrendingAnime($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: TRENDING_DESC, type: ANIME, isAdult: false) {
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
    }
  }
}''';

  final http.Client _httpClient;

  /// Creates the service. Pass a custom [client] to mock in tests.
  AnilistApiService({http.Client? client})
    : _httpClient = client ?? http.Client();

  /// Fetches the top [perPage] trending anime.
  ///
  /// Throws [AnilistException] if the API returns a non-200 status.
  /// Network errors from [http.Client] propagate as-is.
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

    // Safe drill: data → Page → media
    final data = decoded['data'] as Map<String, dynamic>?;
    final page0 = data?['Page'] as Map<String, dynamic>?;
    final mediaList = page0?['media'] as List<dynamic>? ?? const [];

    return mediaList
        .map((raw) => Anime.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  /// Releases the underlying HTTP connection pool.
  /// Call this when the owning widget is disposed.
  void dispose() => _httpClient.close();
}

// ════════════════════════════════════════════════════════════════════════════
//  Exception
// ════════════════════════════════════════════════════════════════════════════

/// Thrown when AniList returns an unexpected HTTP status code.
class AnilistException implements Exception {
  final String message;
  final int? statusCode;

  const AnilistException(this.message, {this.statusCode});

  @override
  String toString() => 'AnilistException($statusCode): $message';
}
