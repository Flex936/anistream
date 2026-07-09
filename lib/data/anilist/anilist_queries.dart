/// Single source of truth for every AniList GraphQL fragment/query/mutation
/// string. Previously `AnilistTrackerService` hand-wrote its own ad hoc
/// query/mutation text duplicating fields already defined for
/// `AnilistQueryService` — a schema change could silently break one and not
/// the other.
abstract final class AnilistFragments {
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

abstract final class AnilistQueries {
  static const String trending =
      '''
    query GetTrendingAnime(\$page: Int, \$perPage: Int, \$bannedGenres: [String]) {
      Page(page: \$page, perPage: \$perPage) { media(sort: TRENDING_DESC, type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, genre_not_in: \$bannedGenres) { ${AnilistFragments.mediaCore} } }
    }''';

  static const String seasonPopular =
      '''
    query GetSeasonPopular(\$page: Int, \$perPage: Int, \$season: MediaSeason, \$seasonYear: Int, \$bannedGenres: [String]) {
      Page(page: \$page, perPage: \$perPage) { media(season: \$season, seasonYear: \$seasonYear, sort: POPULARITY_DESC, type: ANIME, isAdult: false, genre_not_in: \$bannedGenres) { ${AnilistFragments.mediaCore} } }
    }''';

  static const String allTimePopular =
      '''
    query GetAllTimePopular(\$page: Int, \$perPage: Int, \$bannedGenres: [String]) {
      Page(page: \$page, perPage: \$perPage) { media(sort: POPULARITY_DESC, type: ANIME, isAdult: false, genre_not_in: \$bannedGenres) { ${AnilistFragments.mediaCore} } }
    }''';

  static const String search =
      '''
    query (\$search: String, \$bannedGenres: [String], \$minScore: Int, \$status: MediaStatus, \$seasonYear: Int) {
      Page(page: 1, perPage: 15) { media(search: \$search, type: ANIME, sort: SEARCH_MATCH, isAdult: false, genre_not_in: \$bannedGenres, status_not: NOT_YET_RELEASED, averageScore_greater: \$minScore, status: \$status, seasonYear: \$seasonYear) { ${AnilistFragments.mediaCore} } }
    }''';

  static const String userWatchlistPaged =
      '''
    query (\$userId: Int, \$status: MediaListStatus, \$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) {
        pageInfo { hasNextPage }
        mediaList(userId: \$userId, type: ANIME, status: \$status, sort: [MEDIA_TITLE_ROMAJI, MEDIA_ID_DESC]) {
          progress
          media { ${AnilistFragments.mediaCore} genres }
        }
      }
    }''';

  static const String currentlyAiring = r'''
    query GetCurrentlyAiring($page: Int, $perPage: Int, $currentSeason: MediaSeason, $currentYear: Int, $bannedGenres: [String]) {
      Page(page: $page, perPage: $perPage) { media(type: ANIME, season: $currentSeason, seasonYear: $currentYear, sort: TRENDING_DESC, countryOfOrigin: "JP", isAdult: false, genre_not_in: $bannedGenres, format_not_in: [SPECIAL, OVA, ONA, MOVIE]) { id idMal title { romaji english } synonyms coverImage { extraLarge large } bannerImage description episodes status nextAiringEpisode { episode airingAt } } }
    }''';

  static const String viewerId = 'query { Viewer { id } }';

  static const String mediaListEntryStatus = r'''
    query ($mediaId: Int) {
      Media(id: $mediaId) { mediaListEntry { status progress } }
    }
  ''';

  static const String mediaProgress = r'''
    query ($id: Int) { Media(id: $id) { mediaListEntry { progress } } }
  ''';

  static const String saveMediaListEntry = r'''
    mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) {
      SaveMediaListEntry (mediaId: $mediaId, progress: $progress, status: $status) { id }
    }
  ''';
}
