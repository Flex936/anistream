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
  final int? idMal;
  final AnimeTitle title;
  final AnimeCoverImage? coverImage;
  final String? bannerImage;
  final String? description;
  final int? episodes;
  final String? status;
  final String? format;
  final int? averageScore;
  final List<String>? genres;
  final List<String>? synonyms;
  final NextAiringEpisode? nextAiringEpisode;

  const Anime({
    required this.id,
    this.idMal,
    required this.title,
    this.coverImage,
    this.bannerImage,
    this.description,
    this.episodes,
    this.status,
    this.format,
    this.averageScore,
    this.genres,
    this.synonyms,
    this.nextAiringEpisode,
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    final rawTitle = json['title'] as Map<String, dynamic>?;
    final rawCover = json['coverImage'] as Map<String, dynamic>?;
    final rawNextEp = json['nextAiringEpisode'] as Map<String, dynamic>?;

    return Anime(
      id: (json['id'] as num).toInt(),
      idMal: (json['idMal'] as num?)?.toInt(),
      title: rawTitle != null
          ? AnimeTitle.fromJson(rawTitle)
          : const AnimeTitle(),
      coverImage: rawCover != null ? AnimeCoverImage.fromJson(rawCover) : null,
      bannerImage: json['bannerImage'] as String?,
      description: json['description'] as String?,
      episodes: (json['episodes'] as num?)?.toInt(),
      status: json['status'] as String?,
      format: json['format'] as String?,
      averageScore: (json['averageScore'] as num?)?.toInt(),
      genres: (json['genres'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      synonyms: (json['synonyms'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      nextAiringEpisode: rawNextEp != null
          ? NextAiringEpisode.fromJson(rawNextEp)
          : null,
    );
  }
}
