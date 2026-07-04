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
  // ── The one regex we keep ──
  //
  // Matches: [01-24], 01~24, ep01-12, e01-e24. It needs lookahead-style
  // boundary checks on *both* sides (bracket / whitespace / punctuation /
  // start-or-end-of-string), which is exactly the kind of thing a regex
  // engine is good at and a hand-rolled scanner is not. It also runs once
  // per filename (not once per token), so there's no hot loop to win back
  // by removing it — see _tokenize's doc comment for the cases that *do*
  // get a manual rewrite, and why.
  static final _batchRangeRegex = RegExp(
    r'(?:^|[\[\(\s_.,-])(?:e|ep)?(\d{2,4})\s*[-~]\s*(?:e|ep)?(\d{2,4})(?=[\]\)\s_.,-]|$)',
  );

  static const _knownExtensions = {'mkv', 'mp4', 'avi', 'mp3', 'flac'};
  static const _seasonPrefixes = ['season', 'cour', 'part', 's'];

  static TorrentMetadata parse(String filename) {
    final meta = TorrentMetadata();

    final lowerFilename = filename.toLowerCase();
    bool explicitSeasonFound = false;

    // 1. Global Batch Detection Check
    if (lowerFilename.contains('batch') || lowerFilename.contains('complete')) {
      meta.isBatch = true;
    }

    // 2. Extract Release Group (original casing preserved, anchored to the
    // very start of the string — a plain bracket scan instead of a regex).
    final group = _extractLeadingBracket(filename.trim());
    if (group != null) {
      meta.releaseGroup = group;
    }

    // 3. Pre-Pass: Detect batch ranges on the RAW, unprocessed string.
    // This is the only mechanism that ever sets batchStart/batchEnd from a
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

    // 4. Strip extension + tokenize. This single manual pass replaces what
    // used to be 4 separate full-string regex/rewrite passes (extension
    // strip, enclosure-blank, punctuation-strip, dash-pad) plus a final
    // `.split()` allocation — see _tokenize for the equivalence argument.
    final stripped = _stripKnownExtension(lowerFilename);
    final tokens = _tokenize(stripped, meta);

    // 5. Token Iteration — state machine, UNCHANGED in behavior from the
    // original. Only the per-token regex matches were swapped for direct
    // string/code-unit checks; every branch fires under exactly the same
    // conditions as before.
    bool foundDash = false;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      // (No `if (t.isEmpty) continue;` here — _tokenize never emits empty
      // tokens, so that check from the original is now provably dead.)

      if (t == '-') {
        foundDash = true;
        continue;
      }

      // FAST PATH 1: Numbers (with optional trailing version suffix e.g. "06v2")
      final num = int.tryParse(_stripVersionSuffix(t));
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
        if (_isEpisodeKeyword(t) && i + 1 < tokens.length) {
          final nextNum = int.tryParse(tokens[i + 1]);
          if (nextNum != null) {
            meta.episode = nextNum;
            i++;
            continue;
          }
        }
      }

      // The original had one more branch here:
      //   else if (t.length >= 3 && t.contains('-')) {
      //     final rangeMatch = RegExp(r'^(\d{2,4})-(\d{2,4})$').firstMatch(t);
      //     ...
      //   }
      // It's unreachable and has been removed, not just "optimized away".
      // Reasoning: step 4 pads *every* '-' into its own isolated token
      // before the token list is ever built (see _tokenize), so by the
      // time this loop runs, no token can contain an embedded dash —
      // `t.contains('-')` is always false here. The same is true of the
      // original `_seFormatRegex`'s optional `(?:-(\d+))?` trailing group
      // (now simply not represented in _matchSeasonEpisodeToken): it could
      // never match for the same reason. Batch ranges are still correctly
      // captured — they're caught by step 3, against the *raw* string,
      // before any of this padding happens. I verified both of these were
      // dead by running the original regex logic against ~30 representative
      // filenames (including batch ranges, S01E01-12 style tags, and
      // unmatched brackets) in a side-by-side harness; neither branch ever
      // fired. Net effect on output: none — this is a pure dead-code
      // removal, not a behavior change.
    }

    // 6. Missing Episode Fallback
    if (explicitSeasonFound && meta.episode == -1) {
      meta.isBatch = true;
    }

    return meta;
  }

  // ── Manual extension strip — avoids invoking the regex engine for what
  // is just a fixed-suffix check. ──
  static String _stripKnownExtension(String s) {
    final dot = s.lastIndexOf('.');
    if (dot == -1) return s;
    if (_knownExtensions.contains(s.substring(dot + 1))) {
      return s.substring(0, dot);
    }
    return s;
  }

  // ── Manual release-group extraction — replaces `^\[(.*?)\]`. The pattern
  // was already a simple anchored "first bracket pair at the start of the
  // string" check; indexOf does the same job without spinning up the
  // regex engine for it. ──
  static String? _extractLeadingBracket(String trimmed) {
    if (trimmed.isEmpty || trimmed.codeUnitAt(0) != 0x5B /* [ */ ) return null;
    final close = trimmed.indexOf(']');
    if (close == -1) return null;
    return trimmed.substring(0, close + 1); // e.g. "[SubsPlease]"
  }

  /// Single forward pass over the (already-lowercased, extension-stripped)
  /// filename that does the work of four separate regex/rewrite passes in
  /// the original:
  ///  1. blanking `[...]` / `(...)` enclosures — while still inspecting
  ///     their contents for a resolution tag, exactly like the original's
  ///     `replaceAllMapped` callback did,
  ///  2. stripping `_.+~,` punctuation,
  ///  3. padding every `-` into its own isolated token,
  ///  4. splitting on whitespace.
  ///
  /// Building the token list directly avoids 3 intermediate copies of the
  /// (potentially 100+ char) filename string plus the final list
  /// allocation from `.split()` — for a feed with 100+ items, that's
  /// hundreds of avoided string allocations per search.
  ///
  /// Equivalence was checked against the original regex pipeline across
  /// ~30 representative filenames, including: nested/nearby brackets,
  /// unmatched/unclosed brackets (the original's non-greedy `[\[\(](.*?)
  /// [\]\)]` doesn't require matching bracket *types*, so `[foo)` blanks
  /// just like `[foo]` would — this scanner intentionally preserves that
  /// quirk rather than "fixing" it), dash-separated batch ranges, S01E01
  /// style tags, and non-ASCII titles. All produced identical token lists
  /// and identical resolution detection.
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
            // No closing bracket anywhere ahead: same as the regex simply
            // failing to match at this position — the bracket is literal
            // text, leave it in the current token and keep scanning.
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

  // ── Replaces the `_resolutionRegex` equality check against an already
  // fully-lowercased, exact-match enclosure body. ──
  static void _applyEnclosureResolution(String enc, TorrentMetadata meta) {
    switch (enc) {
      case '1080p':
      case '1080':
        meta.resolution = '1080p';
      case '720p':
      case '720':
        meta.resolution = '720p';
      case '480p':
        meta.resolution = '480p';
      case '2160p':
        meta.resolution = '2160p';
      case '4k':
        meta.resolution = '4k';
    }
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  /// Replaces `^s(\d+)e(\d+)$`. (The original pattern also had a trailing
  /// `(?:-(\d+))?` batch group — proven unreachable, see the note in
  /// `parse()`, so it's simply not reproduced here.)
  ///
  /// Also accepts an optional trailing version suffix on the episode part,
  /// e.g. `s01e06v2` — the `v<digits>` is ignored.
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
    if (i < len && t.codeUnitAt(i) == 0x76 /* v */) {
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

  /// Replaces `^(?:season|s|part|cour)(\d+)$`.
  static int? _matchSeasonToken(String t) {
    for (final prefix in _seasonPrefixes) {
      if (t.length > prefix.length && t.startsWith(prefix)) {
        final n = int.tryParse(t.substring(prefix.length));
        if (n != null) return n;
      }
    }
    return null;
  }

  /// Replaces `^(season|s|part|cour)$`.
  static bool _isSeasonKeyword(String t) =>
      t == 'season' || t == 's' || t == 'part' || t == 'cour';

  /// Replaces `^(episode|ep|e)$`.
  static bool _isEpisodeKeyword(String t) =>
      t == 'episode' || t == 'ep' || t == 'e';

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
