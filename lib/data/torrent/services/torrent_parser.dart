class TorrentMetadata {
  String releaseGroup = 'Unknown';
  String resolution = 'Unknown';
  int season = 1;
  int episode = -1;
  bool isBatch = false;
  int batchStart = -1;
  int batchEnd = -1;
}

abstract final class TorrentParser {
  // ── Pre-compiled Regular Expressions (Compiled ONCE into RAM) ──
  static final _extRegex = RegExp(
    r'\.(mkv|mp4|avi|mp3|flac)$',
    caseSensitive: false,
  );
  static final _enclosuresRegex = RegExp(r'[\[\(](.*?)[\]\)]');
  static final _punctuationRegex = RegExp(r'[_.+~]');
  static final _whitespaceRegex = RegExp(r'\s+');

  // Token Validators
  static final _resolutionRegex = RegExp(
    r'^(1080p|720p|480p|2160p|4k)$',
    caseSensitive: false,
  );
  static final _seFormatRegex = RegExp(
    r'^s(\d+)e(\d+)(?:-(\d+))?$',
    caseSensitive: false,
  );
  static final _rangeRegex = RegExp(r'^(\d{2,4})-(\d{2,4})$');
  static final _seasonKeywordRegex = RegExp(
    r'^(season|s|part|cour)$',
    caseSensitive: false,
  );
  static final _episodeKeywordRegex = RegExp(
    r'^(episode|ep|e)$',
    caseSensitive: false,
  );

  static TorrentMetadata parse(String filename) {
    final meta = TorrentMetadata();

    // 1. Strip the file extension
    String text = filename.replaceAll(_extRegex, '');

    // 2. Extract and analyze enclosures [ ] and ( )
    final enclosures = <String>[];
    text = text.replaceAllMapped(_enclosuresRegex, (match) {
      enclosures.add(match.group(1)!);
      return ' '; // Replace with space to prevent token merging
    });

    if (enclosures.isNotEmpty && filename.trim().startsWith('[')) {
      meta.releaseGroup = '[${enclosures.first}]';
    }

    for (final enc in enclosures) {
      final low = enc.toLowerCase();
      if (_resolutionRegex.hasMatch(low) || low == '1080' || low == '720') {
        meta.resolution = low == '1080'
            ? '1080p'
            : (low == '720' ? '720p' : low);
      }
      if (low.contains('batch') || low.contains('complete')) {
        meta.isBatch = true;
      }
    }

    // 3. Prepare string for tokenization
    // Replace punctuation with spaces, but carefully pad dashes so they become isolated state tokens
    text = text.replaceAll(_punctuationRegex, ' ');
    text = text.replaceAll('-', ' - ');

    final tokens = text
        .split(_whitespaceRegex)
        .where((t) => t.isNotEmpty)
        .toList();

    // 4. Token Iteration (State Machine)
    bool foundDash = false;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];

      // A. State tracker
      if (t == '-') {
        foundDash = true;
        continue;
      }

      // B. Check standard S01E01 format
      final seMatch = _seFormatRegex.firstMatch(t);
      if (seMatch != null) {
        meta.season = int.parse(seMatch.group(1)!);
        meta.episode = int.parse(seMatch.group(2)!);
        if (seMatch.group(3) != null) {
          meta.isBatch = true;
          meta.batchStart = meta.episode;
          meta.batchEnd = int.parse(seMatch.group(3)!);
        }
        continue;
      }

      // C. Check explicit Season keywords (e.g., "Season 2")
      if (_seasonKeywordRegex.hasMatch(t) && i + 1 < tokens.length) {
        final nextNum = int.tryParse(tokens[i + 1]);
        if (nextNum != null) {
          meta.season = nextNum;
          i++; // Consume the number token
          continue;
        }
      }

      // D. Check explicit Episode keywords (e.g., "Episode 12")
      if (_episodeKeywordRegex.hasMatch(t) && i + 1 < tokens.length) {
        final nextNum = int.tryParse(tokens[i + 1]);
        if (nextNum != null) {
          meta.episode = nextNum;
          i++;
          continue;
        }
      }

      // E. Check Batch Range (e.g., "01-12")
      final rangeMatch = _rangeRegex.firstMatch(t);
      if (rangeMatch != null) {
        meta.isBatch = true;
        meta.batchStart = int.parse(rangeMatch.group(1)!);
        meta.batchEnd = int.parse(rangeMatch.group(2)!);
        continue;
      }

      // F. Check Standalone Number
      final num = int.tryParse(t);
      if (num != null) {
        // Ignore stray video resolutions masquerading as numbers
        if (num == 1080 || num == 720 || num == 480 || num == 2160) continue;
        // Ignore modern years
        if (num > 1980 && num < 2030) continue;

        if (foundDash && meta.episode == -1) {
          // If we recently passed a semantic dash, this is highly likely the episode (e.g., "Anime Title - 12")
          meta.episode = num;
        } else if (meta.episode == -1) {
          // Continuously overwrite. Because episodes are at the end of filenames, this overwrites numbers in titles (e.g., "Mob Psycho 100")
          meta.episode = num;
        }
      }
    }

    // 5. Keyword fallback check
    if (filename.toLowerCase().contains('batch') ||
        filename.toLowerCase().contains('complete')) {
      meta.isBatch = true;
    }

    return meta;
  }
}
