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
  // ── Pre-compiled Regular Expressions (Optimized: NO caseSensitive flags needed) ──
  static final _extRegex = RegExp(r'\.(mkv|mp4|avi|mp3|flac)$');
  static final _enclosuresRegex = RegExp(r'[\[\(](.*?)[\]\)]');
  static final _punctuationRegex = RegExp(r'[_.+~,]');
  static final _whitespaceRegex = RegExp(r'\s+');

  // Matches: [01-24], 01~24, ep01-12, e01-e24
  static final _batchRangeRegex = RegExp(
    r'(?:^|[\[\(\s_.,-])(?:e|ep)?(\d{2,4})\s*[-~]\s*(?:e|ep)?(\d{2,4})(?=[\]\)\s_.,-]|$)',
  );

  static final _resolutionRegex = RegExp(r'^(1080p|720p|480p|2160p|4k)$');
  static final _seFormatRegex = RegExp(r'^s(\d+)e(\d+)(?:-(\d+))?$');
  static final _sFormatRegex = RegExp(r'^(?:season|s|part|cour)(\d+)$');
  static final _seasonKeywordRegex = RegExp(r'^(season|s|part|cour)$');
  static final _episodeKeywordRegex = RegExp(r'^(episode|ep|e)$');
  static final _rangeRegex = RegExp(r'^(\d{2,4})-(\d{2,4})$');

  static TorrentMetadata parse(String filename) {
    final meta = TorrentMetadata();

    // 1. Lowercase exactly ONCE to speed up all subsequent string/regex operations
    final lowerFilename = filename.toLowerCase();
    bool explicitSeasonFound = false;

    // 2. Global Batch Detection Check
    if (lowerFilename.contains('batch') || lowerFilename.contains('complete')) {
      meta.isBatch = true;
    }

    // 3. Extract Release Group (Using original filename to preserve casing)
    final firstEnclosureMatch = RegExp(
      r'^\[(.*?)\]',
    ).firstMatch(filename.trim());
    if (firstEnclosureMatch != null) {
      meta.releaseGroup = '[${firstEnclosureMatch.group(1)}]';
    }

    // 4. Pre-Pass: Detect batch ranges
    final rangeMatches = _batchRangeRegex.allMatches(lowerFilename);
    for (final m in rangeMatches) {
      final start = int.tryParse(m.group(1)!);
      final end = int.tryParse(m.group(2)!);
      if (start != null && end != null && start < end) {
        meta.isBatch = true;
        meta.batchStart = start;
        meta.batchEnd = end;
      }
    }

    // 5. Clean text for tokenization
    String text = lowerFilename.replaceAll(_extRegex, '');

    text = text.replaceAllMapped(_enclosuresRegex, (match) {
      final enc = match.group(1)!;
      if (_resolutionRegex.hasMatch(enc) || enc == '1080' || enc == '720') {
        meta.resolution = enc == '1080'
            ? '1080p'
            : (enc == '720' ? '720p' : enc);
      }
      return ' '; // Blank out enclosure
    });

    text = text.replaceAll(_punctuationRegex, ' ');
    text = text.replaceAll('-', ' - ');

    // Split without allocating extra `.where()` lists
    final tokens = text.split(_whitespaceRegex);

    // 6. Token Iteration (Optimized State Machine)
    bool foundDash = false;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.isEmpty) {
        continue;
      }

      if (t == '-') {
        foundDash = true;
        continue;
      }

      // FAST PATH 1: Numbers (Extremely fast to check before hitting regexes)
      final num = int.tryParse(t);
      if (num != null) {
        if (num == 1080 || num == 720 || num == 480 || num == 2160) {
          continue;
        }
        if (num > 1980 && num < 2030) {
          continue;
        }

        if (foundDash && meta.episode == -1) {
          meta.episode = num;
        } else if (meta.episode == -1) {
          meta.episode = num;
        }
        continue;
      }

      // FAST PATH 2: Gate heavy regex checks by looking at the first character
      final char0 = t[0];

      if (char0 == 's' || char0 == 'p' || char0 == 'c') {
        final seMatch = _seFormatRegex.firstMatch(t);
        if (seMatch != null) {
          meta.season = int.parse(seMatch.group(1)!);
          meta.episode = int.parse(seMatch.group(2)!);
          explicitSeasonFound = true;
          if (seMatch.group(3) != null) {
            meta.isBatch = true;
            meta.batchStart = meta.episode;
            meta.batchEnd = int.parse(seMatch.group(3)!);
          }
          continue;
        }

        final sMatch = _sFormatRegex.firstMatch(t);
        if (sMatch != null) {
          meta.season = int.parse(sMatch.group(1)!);
          explicitSeasonFound = true;
          continue;
        }

        if (_seasonKeywordRegex.hasMatch(t) && i + 1 < tokens.length) {
          final nextNum = int.tryParse(tokens[i + 1]);
          if (nextNum != null) {
            meta.season = nextNum;
            explicitSeasonFound = true;
            i++;
            continue;
          }
        }
      } else if (char0 == 'e') {
        if (_episodeKeywordRegex.hasMatch(t) && i + 1 < tokens.length) {
          final nextNum = int.tryParse(tokens[i + 1]);
          if (nextNum != null) {
            meta.episode = nextNum;
            i++;
            continue;
          }
        }
      } else if (t.length >= 3 && t.contains('-')) {
        final rangeMatch = _rangeRegex.firstMatch(t);
        if (rangeMatch != null) {
          meta.isBatch = true;
          meta.batchStart = int.parse(rangeMatch.group(1)!);
          meta.batchEnd = int.parse(rangeMatch.group(2)!);
          continue;
        }
      }
    }

    // 7. Missing Episode Fallback
    if (explicitSeasonFound && meta.episode == -1) {
      meta.isBatch = true;
    }

    return meta;
  }
}
