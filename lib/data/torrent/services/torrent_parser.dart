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
  //
  // The {2,4} digit-count floor is deliberate and load-bearing, not just a
  // sane-length guess — DO NOT relax it to {1,4} to catch rare single-digit
  // batch ranges (e.g. a 6-episode OVA batched as "1-6"). Doing so would
  // also make this regex match "Series 2 - 05" — a bare sequel-cour digit
  // baked into the title, followed by a dash then the real episode — as if
  // it were a batch range "2-5". Confirmed by running both shapes through
  // this pattern side-by-side: {1,4} turns "Shingeki no Kyojin 2 - 05" into
  // a false batch classification; {2,4} correctly leaves it alone and lets
  // the token loop below (see `episodeIsConfident`) resolve it as episode 5.
  static final _batchRangeRegex = RegExp(
    r'(?:^|[\[\(\s_.,-])(?:e|ep)?(\d{2,4})\s*[-~]\s*(?:e|ep)?(\d{2,4})(?=[\]\)\s_.,-]|$)',
  );

  static const _knownExtensions = {'mkv', 'mp4', 'avi', 'mp3', 'flac'};
  static const _seasonPrefixes = ['season', 'cour', 'part', 's'];

  // ── Bare (unbracketed) numbers that should never be treated as episode
  // candidates because they're almost certainly a resolution tag instead —
  // e.g. "Show.Name.540.05.WEB-DL.mkv" from a scene-style release that
  // skips brackets entirely. This is deliberately broader than the set
  // _applyEnclosureResolution actually surfaces into meta.resolution: it
  // only needs to keep these values from being *mistaken for an episode*,
  // not to make every one of them user-visible. The original list was just
  // {1080, 720, 480, 2160} — 360/540/576/1440/4320 sailed straight through
  // into episode-candidate territory (a bare "540", a real if less common
  // BD-encode height, would previously have overwritten the true episode
  // number if it appeared before it with no dash in between). ──
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

    // 5. Token Iteration — state machine.
    //
    // `episodeIsConfident` tracks whether the current meta.episode came
    // from an unambiguous marker (S01E06, a bare E06/EP12 tag, or the
    // "episode"/"ep"/"e" keyword followed by a number) as opposed to a
    // bare, structurally-unmarked digit. Only a *confident* match is
    // allowed to stick once something later tries to overwrite it — a bare
    // digit is always still just a guess and can be superseded by a better
    // signal found later in the same filename.
    //
    // Previously `foundDash` was tracked but never actually changed which
    // branch ran below — both arms of the old if/else-if did the exact
    // same `meta.episode = num` assignment, so the *first* bare digit
    // anywhere in the filename won and could never be replaced. That meant
    // any title with its own embedded sequel/cour digit before the real
    // episode marker — "Shingeki no Kyojin 2 - 05", "Symphogear 2 - 12" —
    // had its episode permanently misread as 2, not 5/12, causing the
    // scoring engine's episode-match check to reject the correct torrent
    // outright. `foundDash` now actually does something: a number *after*
    // a dash overwrites a tentative pre-dash guess, since the dash is the
    // strongest positional signal fansub naming gives us for "this is the
    // real episode."
    bool foundDash = false;
    bool episodeIsConfident = false;

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
        // Season - 05". Never caught by FAST PATH 1 above (int.tryParse
        // rejects the "nd"/"rd"/"th"/"st" suffix), so this previously fell
        // straight through untouched, leaving meta.season stuck at its
        // default of 1 for any anime whose sequel season is titled this
        // way — which AniList (and the fansub groups mirroring its
        // titling) does very commonly. Gated on the very next token being
        // "season" so an unrelated ordinal like "1st Anniversary Edition"
        // is never mistaken for a season marker.
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

  // ── Widened from an exact-string equality check against the whole
  // enclosure body to a per-word scan. Some releases pack multiple
  // space/dot/dash-separated descriptors into a single bracket pair
  // instead of one tag per bracket — e.g. "[BD 1080p FLAC]" or "[BDRip
  // 1080p HEVC]" — and the old `switch (enc) { case '1080p': ... }` only
  // ever matched when the enclosure's *entire* contents equaled exactly
  // "1080p", so any compound tag silently left meta.resolution at
  // "Unknown". Splitting on non-alphanumeric characters and checking each
  // resulting word keeps the common single-tag case working identically
  // (no separator inside "1080p" ⇒ one "word" ⇒ same match as before)
  // while also catching the compound form. ──
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

  /// Bare `eNN` / `epNN` with no season prefix at all — e.g. "e06", "ep12"
  /// used as a standalone episode tag instead of either a plain number or
  /// a full "S01E06". Previously unhandled: `_isEpisodeKeyword` only
  /// matches the literal tokens "episode"/"ep"/"e" and expects the number
  /// as a *separate*, following token, so "e06"/"ep12" as one fused token
  /// matched neither that check nor `_matchSeasonEpisodeToken` (which
  /// requires a leading `s`) — it was silently dropped, leaving
  /// meta.episode at -1 for releases using this tagging style.
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

  /// Ordinal season prefix — "2nd", "3rd", "4th", "21st" — parsed on its
  /// own; the caller is responsible for also checking that the *next*
  /// token is literally "season" before treating this as a season marker,
  /// so an unrelated ordinal like "1st Anniversary Edition" is never
  /// mistaken for one.
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
