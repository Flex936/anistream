import 'package:media_kit/media_kit.dart';

class ParsedTrack {
  final String mainTitle;
  final String? subTitle;

  const ParsedTrack({required this.mainTitle, this.subTitle});
}

class TrackNameParser {
  // Maps standard 2- and 3-letter ISO codes to readable names.
  static String _normalizeLanguage(String lang) {
    final l = lang.toLowerCase().trim();
    return switch (l) {
      'eng' || 'en' || 'english' => 'English',
      'jpn' || 'ja' || 'japanese' => 'Japanese',
      'spa' || 'es' || 'spanish' => 'Spanish',
      'fre' || 'fra' || 'fr' || 'french' => 'French',
      'ger' || 'de' || 'deu' || 'german' => 'German',
      'por' || 'pt' || 'portuguese' => 'Portuguese',
      'ita' || 'it' || 'italian' => 'Italian',
      'rus' || 'ru' || 'russian' => 'Russian',
      'chi' || 'zh' || 'zho' || 'chinese' => 'Chinese',
      'ara' || 'ar' || 'arabic' => 'Arabic',
      'und' || 'unk' || '' => '',
      _ => _capitalize(lang),
    };
  }

  /// Prettifies an audio track's raw title/language into a display-ready
  /// [ParsedTrack]. Takes plain strings rather than a concrete track
  /// type so both the desktop/mpv path (`AudioTrack.title`/`.language`)
  /// and the ExoPlayer path (`VideoAudioTrack.label`/`.language`) share
  /// this exact naming logic, instead of `ExoTheaterScreen` carrying a
  /// second copy of it.
  ///
  /// Deliberately says nothing about "no track selected yet" — the old
  /// null-`AudioTrack?` short-circuit that used to return 'Auto' here —
  /// since that's a selection-state concern each caller already has to
  /// handle for its own engine (mpv genuinely has an "auto" track mode;
  /// ExoPlayer's reported tracks always have exactly one selected once
  /// loaded), not something a track-naming helper should guess at from a
  /// track that might legitimately just have no title or language of
  /// its own.
  static ParsedTrack parseAudio({String? title, String? language}) {
    String trimmedTitle = title?.trim() ?? '';
    final lang = _normalizeLanguage(language?.trim() ?? '');

    // 1. Remove release group brackets completely
    trimmedTitle = trimmedTitle.replaceAll(RegExp(r'\[.*?\]'), '').trim();

    // 2. Format: "Japanese / 5.1ch Opus" or "Inner Silence / 5.1ch Opus"
    if (trimmedTitle.contains('/')) {
      final parts = trimmedTitle.split('/');
      String main = parts[0].trim();
      String sub = parts.sublist(1).join(' • ').trim();

      sub = sub.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' / ', ' • ');

      // If the main title isn't a language (e.g. "Inner Silence"), bump it to the subtitle
      if (lang.isNotEmpty && _normalizeLanguage(main) != lang) {
        sub = '$main • $sub';
        main = lang;
      }

      return ParsedTrack(
        mainTitle: _capitalize(main.isEmpty ? 'Audio Track' : main),
        subTitle: sub.isNotEmpty ? sub : null,
      );
    }

    // 3. Technical jargon fallback (e.g. "Surround 5.1")
    final lower = trimmedTitle.toLowerCase();
    if (lower == 'surround 5.1' ||
        lower == 'stereo' ||
        lower.contains('opus') ||
        lower.contains('aac') ||
        lower.contains('flac')) {
      return ParsedTrack(
        mainTitle: lang.isEmpty ? 'Audio Track' : lang,
        subTitle: trimmedTitle,
      );
    }

    // 4. Default fallback
    return ParsedTrack(
      mainTitle: lang.isEmpty ? (trimmedTitle.isEmpty ? 'Audio Track' : trimmedTitle) : lang,
      subTitle: lang.isEmpty || trimmedTitle.toLowerCase() == lang.toLowerCase()
          ? null
          : trimmedTitle,
    );
  }

  static ParsedTrack parseSubtitle(SubtitleTrack? t) {
    if (t == null) return const ParsedTrack(mainTitle: 'Auto');
    if (t.id == 'no') return const ParsedTrack(mainTitle: 'Disabled');

    String title = t.title?.trim() ?? '';
    final lang = _normalizeLanguage(t.language?.trim() ?? '');

    // 1. Remove release group brackets
    title = title.replaceAll(RegExp(r'\[.*?\]'), '').trim();

    // 2. Extract technical/stylistic info from parentheses
    final parenMatch = RegExp(r'\((.*?)\)').firstMatch(title);
    String? extractedSub;
    if (parenMatch != null) {
      extractedSub = parenMatch.group(1)?.trim();
      title = title.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    }

    // 3. Standardize generic names
    final lower = title.toLowerCase();
    if (lower.contains('sign') || lower.contains('song')) {
      title = 'Signs & Songs';
    } else if (lower.contains('full') ||
        lower.contains('dialogue') ||
        lower == 'english' ||
        lower == 'japanese') {
      title = 'Full Subtitles';
    }

    // 4. Build final strings
    String finalMain = '';
    String finalSub = '';

    if (lang.isNotEmpty) {
      finalMain = lang; // The primary text is now the Language (e.g. "English")
      finalSub = title.isNotEmpty ? title : 'Full Subtitles';
    } else {
      finalMain = title.isNotEmpty ? title : 'Subtitle Track';
    }

    // 5. Append extracted parenthesis to the subtitle
    if (extractedSub != null && extractedSub.isNotEmpty) {
      if (finalSub.isNotEmpty) {
        finalSub = '$finalSub • $extractedSub';
      } else {
        finalSub = extractedSub;
      }
    }

    // Edge case cleanup
    if (finalSub.toLowerCase() == finalMain.toLowerCase()) {
      finalSub = '';
    }

    return ParsedTrack(
      mainTitle: _capitalize(finalMain),
      subTitle: finalSub.isNotEmpty ? _capitalize(finalSub) : null,
    );
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}