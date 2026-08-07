/// Parsed metadata extracted from a raw torrent release filename.
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
  // The one regex this parser uses. Matches: [01-24], 01~24, ep01-12,
  // e01-e24. It needs lookahead-style boundary checks on both sides
  // (bracket / whitespace / punctuation / start-or-end-of-string), which
  // is exactly the kind of thing a regex engine is good at and a
  // hand-rolled scanner is not. It also runs once per filename (not once
  // per token), so there's no hot loop to win back by removing it — see
  // _tokenize's doc comment for the cases that do get a manual scan
  // instead, and why.
  //
  // The {2,4} digit-count floor is deliberate and load-bearing, not just
  // a sane-length guess — do not relax it to {1,4} to catch rare
  // single-digit batch ranges (e.g. a 6-episode OVA batched as "1-6").
  // Doing so would also make this regex match "Series 2 - 05" — a bare
  // sequel-cour digit baked into the title, followed by a dash then the
  // real episode — as if it were a batch range "2-5". Verified by running
  // both shapes through this pattern side-by-side: {1,4} turns "Shingeki
  // no Kyojin 2 - 05" into a false batch classification; {2,4} correctly
  // leaves it alone and lets the token loop below (see
  // `episodeIsConfident`) resolve it as episode 5.
  static final _batchRangeRegex = RegExp(
    r'(?:^|[\[\(\s_.,-])(?:e|ep)?(\d{2,4})\s*[-~]\s*(?:e|ep)?(\d{2,4})(?=[\]\)\s_.,-]|$)',
  );

  static const _knownExtensions = {'mkv', 'mp4', 'avi', 'mp3', 'flac'};
  static const _seasonPrefixes = ['season', 'cour', 'part', 's'];

  // Bare (unbracketed) numbers that are never treated as episode
  // candidates because they're almost certainly a resolution tag instead
  // — e.g. "Show.Name.540.05.WEB-DL.mkv" from a scene-style release that
  // skips brackets entirely. This is deliberately broader than the set
  // _applyEnclosureResolution surfaces into meta.resolution: it only
  // needs to keep these values from being mistaken for an episode, not
  // to make every one of them user-visible.
  static const _knownResolutionValues = {
    360,
    480,
    540,
    576,
    720,
    1080,
    1440,
    2160,
    4320,
  };

  static TorrentMetadata parse(String filename) {
    final meta = TorrentMetadata();

    final lowerFilename = filename.toLowerCase();
    bool explicitSeasonFound = false;

    // 1. Global batch detection check.
    if (lowerFilename.contains('batch') || lowerFilename.contains('complete')) {
      meta.isBatch = true;
    }

    // 2. Extract release group (original casing preserved, anchored to the
    // very start of the string — a plain bracket scan instead of a regex).
    final group = _extractLeadingBracket(filename.trim());
    if (group != null) {
      meta.releaseGroup = group;
    }

    // 3. Pre-pass: detect batch ranges on the raw, unprocessed string.
    // This is the only mechanism that sets batchStart/batchEnd from a
    // dash-range — see the note in the token loop below for why.
    for (final m in _batchRangeRegex.allMatches(lowerFilename)) {
      final start = int.tryParse(m.group(1)!);
      final end = int.tryParse(m.group(2)!);
      if (start != null && end != null && start < end) {
        meta.isBatch = true;
        meta.batchStart = start;
        meta.batchEnd = end;
      }
    }

    // 4. Strip extension + tokenize. This single manual pass handles
    // extension stripping, bracket-enclosure blanking (while still
    // inspecting bracket contents for a resolution tag), punctuation
    // stripping, dash isolation, and the final split — see _tokenize for
    // the full behavior and the equivalence testing it was checked
    // against.
    final stripped = _stripKnownExtension(lowerFilename);
    final tokens = _tokenize(stripped, meta);

    // 5. Token iteration — state machine.
    //
    // `episodeIsConfident` tracks whether the current meta.episode came
    // from an unambiguous marker (S01E06, a bare E06/EP12 tag, or the
    // "episode"/"ep"/"e" keyword followed by a number) as opposed to a
    // bare, structurally-unmarked digit. Only a confident match is
    // allowed to stick once something later tries to overwrite it — a
    // bare digit is always still just a guess and can be superseded by a
    // better signal found later in the same filename.
    //
    // `foundDash` tracks whether a literal `-` token has been seen yet: a
    // number appearing after a dash overwrites a tentative pre-dash
    // guess, since the dash is the strongest positional signal fansub
    // naming gives for "this is the real episode" — this is what
    // correctly resolves titles with their own embedded sequel/cour digit
    // before the real episode marker, such as "Shingeki no Kyojin 2 - 05"
    // or "Symphogear 2 - 12", to episode 5/12 rather than 2.
    bool foundDash = false;
    bool episodeIsConfident = false;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      // (No `if (t.isEmpty) continue;` here — _tokenize never emits empty
      // tokens, so that check would be dead.)

      if (t == '-') {
        foundDash = true;
        continue;
      }

      // FAST PATH 1: Numbers (with optional trailing version suffix e.g. "06v2")
      final num = int.tryParse(_stripVersionSuffix(t));
      if (num != null) {
        if (_knownResolutionValues.contains(num)) {
          continue;
        }
        if (num > 1980 && num < 2030) {
          continue;
        }

        // A bare digit is never allowed to clobber a confident match found
        // elsewhere in the filename (S01E06, E06, "ep 06", ...).
        if (!episodeIsConfident) {
          if (foundDash) {
            meta.episode = num;
          } else if (meta.episode == -1) {
            // Tentative: kept only in case no later, better-positioned
            // number ever shows up (e.g. a plain "Series 05.mkv" with no
            // dash at all).
            meta.episode = num;
          }
        }
        continue;
      }

      // FAST PATH 2: Gate heavier checks by first character. Using
      // codeUnitAt instead of t[0] avoids allocating a throwaway
      // single-character String for every token just to compare it.
      final char0 = t.codeUnitAt(0);

      if (char0 == 0x73 /* s */ ||
          char0 == 0x70 /* p */ ||
          char0 == 0x63 /* c */ ) {
        final se = _matchSeasonEpisodeToken(t);
        if (se != null) {
          meta.season = se.season;
          meta.episode = se.episode;
          episodeIsConfident = true;
          explicitSeasonFound = true;
          continue;
        }

        final seasonNum = _matchSeasonToken(t);
        if (seasonNum != null) {
          meta.season = seasonNum;
          explicitSeasonFound = true;
          continue;
        }

        if (_isSeasonKeyword(t) && i + 1 < tokens.length) {
          final nextNum = int.tryParse(tokens[i + 1]);
          if (nextNum != null) {
            meta.season = nextNum;
            explicitSeasonFound = true;
            i++;
            continue;
          }
        }
      } else if (char0 == 0x65 /* e */ ) {
        final epNum = _matchEpisodeToken(t);
        if (epNum != null) {
          if (!episodeIsConfident) {
            meta.episode = epNum;
            episodeIsConfident = true;
          }
          continue;
        }

        if (_isEpisodeKeyword(t) && i + 1 < tokens.length) {
          final nextNum = int.tryParse(tokens[i + 1]);
          if (nextNum != null) {
            meta.episode = nextNum;
            episodeIsConfident = true;
            i++;
            continue;
          }
        }
      } else if (_isDigit(char0)) {
        // Ordinal season prefix: "2nd"/"3rd"/"4th"/"21st" immediately
        // followed by a literal "season" token, e.g. "Show Name 2nd
        // Season - 05" — a common AniList/fansub titling style for
        // sequel seasons. Gated on the very next token being "season" so
        // an unrelated ordinal like "1st Anniversary Edition" is never
        // mistaken for a season marker.
        final ordinal = _matchOrdinalPrefix(t);
        if (ordinal != null &&
            i + 1 < tokens.length &&
            tokens[i + 1] == 'season') {
          meta.season = ordinal;
          explicitSeasonFound = true;
          i++;
          continue;
        }
      }
    }

    // 6. Missing episode fallback.
    if (explicitSeasonFound && meta.episode == -1) {
      meta.isBatch = true;
    }

    return meta;
  }

  // Manual extension strip — avoids invoking the regex engine for what is
  // just a fixed-suffix check.
  static String _stripKnownExtension(String s) {
    final dot = s.lastIndexOf('.');
    if (dot == -1) return s;
    if (_knownExtensions.contains(s.substring(dot + 1))) {
      return s.substring(0, dot);
    }
    return s;
  }

  // Manual release-group extraction: the pattern is just "first bracket
  // pair at the start of the string," so indexOf does the job without
  // spinning up the regex engine for it.
  static String? _extractLeadingBracket(String trimmed) {
    if (trimmed.isEmpty || trimmed.codeUnitAt(0) != 0x5B /* [ */ ) return null;
    final close = trimmed.indexOf(']');
    if (close == -1) return null;
    return trimmed.substring(0, close + 1); // e.g. "[SubsPlease]"
  }

  /// Single forward pass over the (already-lowercased, extension-stripped)
  /// filename that:
  ///  1. blanks `[...]` / `(...)` enclosures while still inspecting their
  ///     contents for a resolution tag,
  ///  2. strips `_.+~,` punctuation,
  ///  3. pads every `-` into its own isolated token,
  ///  4. splits on whitespace,
  /// all in one traversal, building the token list directly rather than
  /// via several intermediate string copies.
  ///
  /// Verified against ~30 representative filenames, including:
  /// nested/nearby brackets, unmatched/unclosed brackets (a non-greedy
  /// bracket match doesn't require matching bracket types, so `[foo)`
  /// blanks just like `[foo]` would — this scanner intentionally
  /// preserves that quirk rather than "fixing" it), dash-separated batch
  /// ranges, S01E01-style tags, and non-ASCII titles.
  static List<String> _tokenize(String text, TorrentMetadata meta) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    final len = text.length;

    void flush() {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    }

    var i = 0;
    while (i < len) {
      final unit = text.codeUnitAt(i);

      switch (unit) {
        case 0x5B: // '['
        case 0x28: // '('
          var j = i + 1;
          var closeIdx = -1;
          while (j < len) {
            final u = text.codeUnitAt(j);
            if (u == 0x5D || u == 0x29) {
              // ']' or ')'
              closeIdx = j;
              break;
            }
            j++;
          }
          if (closeIdx == -1) {
            // No closing bracket anywhere ahead — the bracket is literal
            // text, so it's left in the current token and scanning
            // continues.
            buffer.writeCharCode(unit);
            i++;
          } else {
            _applyEnclosureResolution(text.substring(i + 1, closeIdx), meta);
            flush();
            i = closeIdx + 1;
          }
          continue;

        case 0x2D: // '-' always becomes its own isolated token
          flush();
          tokens.add('-');
          i++;
          continue;

        case 0x5F: // '_'
        case 0x2E: // '.'
        case 0x2B: // '+'
        case 0x7E: // '~'
        case 0x2C: // ','
        case 0x20: // ' '
        case 0x09: // '\t'
        case 0x0A: // '\n'
        case 0x0D: // '\r'
          flush();
          i++;
          continue;

        default:
          buffer.writeCharCode(unit);
          i++;
          continue;
      }
    }

    flush();
    return tokens;
  }

  // Scans each non-alphanumeric-delimited word inside a bracket enclosure
  // for a resolution tag, rather than requiring the enclosure's entire
  // contents to equal the tag exactly. Some releases pack multiple
  // space/dot/dash-separated descriptors into a single bracket pair
  // instead of one tag per bracket — e.g. "[BD 1080p FLAC]" or "[BDRip
  // 1080p HEVC]" — and a per-word scan catches those compound tags while
  // still handling the common single-tag case identically (no separator
  // inside "1080p" means one "word", so the match is the same either way).
  static void _applyEnclosureResolution(String enc, TorrentMetadata meta) {
    for (final word in enc.split(_enclosureWordSplitter)) {
      switch (word) {
        case '1080p':
        case '1080':
          meta.resolution = '1080p';
          return;
        case '720p':
        case '720':
          meta.resolution = '720p';
          return;
        case '480p':
          meta.resolution = '480p';
          return;
        case '2160p':
          meta.resolution = '2160p';
          return;
        case '4k':
          meta.resolution = '4k';
          return;
      }
    }
  }

  static final _enclosureWordSplitter = RegExp(r'[^a-z0-9]+');

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  /// Matches a fused season/episode tag of the form `s01e06`, with an
  /// optional trailing version suffix on the episode part (e.g.
  /// `s01e06v2`, where the `v2` is ignored).
  static ({int season, int episode})? _matchSeasonEpisodeToken(String t) {
    final len = t.length;
    if (t.codeUnitAt(0) != 0x73 /* s */ ) return null;

    var i = 1;
    final seasonStart = i;
    while (i < len && _isDigit(t.codeUnitAt(i))) {
      i++;
    }
    if (i == seasonStart || i >= len || t.codeUnitAt(i) != 0x65 /* e */ ) {
      return null;
    }
    final season = int.parse(t.substring(seasonStart, i));

    i++; // skip 'e'
    final epStart = i;
    while (i < len && _isDigit(t.codeUnitAt(i))) {
      i++;
    }
    if (i == epStart) return null;
    final epEnd = i; // marks the end of the bare episode digits
    // Allow an optional trailing version suffix: v<digits> (e.g. "s01e06v2")
    if (i < len && t.codeUnitAt(i) == 0x76 /* v */ ) {
      final vStart = i + 1;
      var j = vStart;
      while (j < len && _isDigit(t.codeUnitAt(j))) {
        j++;
      }
      if (j > vStart && j == len) {
        // valid v<digits> suffix — consume it so the final `i != len` check passes
        i = j;
      }
    }
    if (i != len) return null;
    final episode = int.parse(t.substring(epStart, epEnd));

    return (season: season, episode: episode);
  }

  /// Matches a bare season tag: `season12`, `s12`, `part2`, `cour2`.
  static int? _matchSeasonToken(String t) {
    for (final prefix in _seasonPrefixes) {
      if (t.length > prefix.length && t.startsWith(prefix)) {
        final n = int.tryParse(t.substring(prefix.length));
        if (n != null) return n;
      }
    }
    return null;
  }

  /// True for a standalone season keyword token: `season`, `s`, `part`,
  /// `cour` — used together with the following token when the number is
  /// space-separated instead of fused (e.g. "Season 2").
  static bool _isSeasonKeyword(String t) =>
      t == 'season' || t == 's' || t == 'part' || t == 'cour';

  /// True for a standalone episode keyword token: `episode`, `ep`, `e` —
  /// used together with the following token when the number is
  /// space-separated instead of fused (e.g. "Episode 6").
  static bool _isEpisodeKeyword(String t) =>
      t == 'episode' || t == 'ep' || t == 'e';

  /// Matches a bare, fused episode tag with no season prefix — `e06`,
  /// `ep12` — used by releases that tag episodes this way instead of
  /// either a plain number or a full `S01E06`.
  static int? _matchEpisodeToken(String t) {
    if (t.length > 2 && t.startsWith('ep')) {
      final n = int.tryParse(t.substring(2));
      if (n != null) return n;
    }
    if (t.length > 1 && t.codeUnitAt(0) == 0x65 /* e */ ) {
      final n = int.tryParse(t.substring(1));
      if (n != null) return n;
    }
    return null;
  }

  /// Matches an ordinal season prefix — "2nd", "3rd", "4th", "21st" —
  /// returning its numeric value. The caller is responsible for also
  /// checking that the next token is literally "season" before treating
  /// this as a season marker, so an unrelated ordinal like "1st
  /// Anniversary Edition" is never mistaken for one.
  static int? _matchOrdinalPrefix(String t) {
    final len = t.length;
    if (len < 3) return null;
    final suffix = t.substring(len - 2);
    if (suffix != 'st' && suffix != 'nd' && suffix != 'rd' && suffix != 'th') {
      return null;
    }
    return int.tryParse(t.substring(0, len - 2));
  }

  /// Strips a trailing version suffix of the form `v<digits>` from a token,
  /// returning the bare numeric string so that e.g. `"06v2"` → `"06"`.
  /// Returns the original token unchanged if the suffix isn't present or the
  /// remaining prefix is empty.
  static String _stripVersionSuffix(String t) {
    final vIdx = t.indexOf('v');
    if (vIdx <= 0) return t; // no 'v', or 'v' at position 0 (not a number)
    final afterV = t.substring(vIdx + 1);
    if (afterV.isEmpty) return t;
    // Only strip if the part after 'v' is all digits and the part before 'v'
    // is also all digits (so we don't mangle tokens like "av1" codec names).
    for (int k = 0; k < afterV.length; k++) {
      if (!_isDigit(afterV.codeUnitAt(k))) return t;
    }
    final base = t.substring(0, vIdx);
    for (int k = 0; k < base.length; k++) {
      if (!_isDigit(base.codeUnitAt(k))) return t;
    }
    return base;
  }
}
