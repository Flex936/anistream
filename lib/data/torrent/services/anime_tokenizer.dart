class TorrentMetadata {
  String releaseGroup = 'Unknown';
  String resolution = 'Unknown';
  int season = 1;
  int episode = -1;
  bool isBatch = false;
  int batchStart = -1;
  int batchEnd = -1;
}

class AnimeTokenizer {
  static TorrentMetadata parse(String filename) {
    final meta = TorrentMetadata();

    // 1. Remove extension
    String text = filename.replaceAll(
      RegExp(r'\.(mkv|mp4|avi|mp3|flac)$', caseSensitive: false),
      '',
    );

    // 2. Extract enclosures [ ] and ( )
    final enclosures = <String>[];
    text = text.replaceAllMapped(RegExp(r'[\[\(](.*?)[\]\)]'), (match) {
      enclosures.add(match.group(1)!);
      return ' '; // Replace with space so tokens don't merge
    });

    // 3. Process Enclosures (Group, Resolution, Batch info)
    if (enclosures.isNotEmpty && filename.trim().startsWith('[')) {
      meta.releaseGroup = '[${enclosures.first}]';
    }

    for (final enc in enclosures) {
      final low = enc.toLowerCase();
      if (low.contains('1080p') || low == '1080') {
        meta.resolution = '1080p';
      } else if (low.contains('720p') || low == '720') {
        meta.resolution = '720p';
      } else if (low.contains('480p') || low == '480') {
        meta.resolution = '480p';
      } else if (low.contains('2160p') || low.contains('4k')) {
        meta.resolution = '2160p';
      }

      if (low.contains('batch') || low.contains('complete')) {
        meta.isBatch = true;
      }
    }

    // 4. Tokenize the remaining text
    // Replace punctuation with spaces, EXCEPT dashes which are important semantic dividers
    text = text.replaceAll(RegExp(r'[_.+~]'), ' ');
    // Pad dashes so they become their own isolated tokens
    text = text.replaceAll('-', ' - ');

    final tokens = text
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    // 5. Analyze Tokens (Left to Right)
    bool foundDash = false;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final low = t.toLowerCase();

      // State tracker
      if (t == '-') {
        foundDash = true;
        continue;
      }

      // Check S01E01 or S01E01-12 format
      final seMatch = RegExp(
        r'^s(\d+)e(\d+)(?:-(\d+))?$',
        caseSensitive: false,
      ).firstMatch(t);
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

      // Check explicit Season (e.g. "Season 2" or "S2")
      if ((low == 'season' || low == 's') && i + 1 < tokens.length) {
        final nextNum = int.tryParse(tokens[i + 1]);
        if (nextNum != null) {
          meta.season = nextNum;
          i++; // Skip the number token since we consumed it
          continue;
        }
      }

      // Check explicit Episode (e.g. "Episode 12" or "Ep12")
      if ((low == 'episode' || low == 'ep' || low == 'e') &&
          i + 1 < tokens.length) {
        final nextNum = int.tryParse(tokens[i + 1]);
        if (nextNum != null) {
          meta.episode = nextNum;
          i++;
          continue;
        }
      }

      // Check Batch Range (e.g. "01-12")
      final rangeMatch = RegExp(r'^(\d{2,3})-(\d{2,3})$').firstMatch(t);
      if (rangeMatch != null) {
        meta.isBatch = true;
        meta.batchStart = int.parse(rangeMatch.group(1)!);
        meta.batchEnd = int.parse(rangeMatch.group(2)!);
        continue;
      }

      // Check Standalone Number
      final num = int.tryParse(t);
      if (num != null) {
        // Ignore resolutions masquerading as text tokens
        if (num == 1080 || num == 720 || num == 480 || num == 2160) continue;
        // Ignore modern years
        if (num > 1980 && num < 2030) continue;

        if (foundDash && meta.episode == -1) {
          // If we recently passed a dash, this is extremely likely to be the episode number (e.g. "Title - 12")
          meta.episode = num;
        } else if (meta.episode == -1) {
          // Keep updating episode with the latest standalone number we find.
          // Because episodes are usually at the end of the string, this naturally overwrites numbers in the title.
          meta.episode = num;
        }
      }
    }

    // Keyword fallback check
    if (filename.toLowerCase().contains('batch') ||
        filename.toLowerCase().contains('complete')) {
      meta.isBatch = true;
    }

    return meta;
  }
}
