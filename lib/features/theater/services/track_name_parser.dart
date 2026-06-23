import 'package:media_kit/media_kit.dart';

class ParsedTrack {
  final String mainTitle;
  final String? subTitle;

  const ParsedTrack({required this.mainTitle, this.subTitle});
}

class TrackNameParser {
  // ── Maps standard 2 and 3 letter ISO codes to readable names ──
  static String _normalizeLanguage(String lang) {
    final l = lang.toLowerCase().trim();
    switch (l) {
      case 'eng':
      case 'en':
      case 'english':
        return 'English';
      case 'jpn':
      case 'ja':
      case 'japanese':
        return 'Japanese';
      case 'spa':
      case 'es':
      case 'spanish':
        return 'Spanish';
      case 'fre':
      case 'fra':
      case 'fr':
      case 'french':
        return 'French';
      case 'ger':
      case 'de':
      case 'deu':
      case 'german':
        return 'German';
      case 'por':
      case 'pt':
      case 'portuguese':
        return 'Portuguese';
      case 'ita':
      case 'it':
      case 'italian':
        return 'Italian';
      case 'rus':
      case 'ru':
      case 'russian':
        return 'Russian';
      case 'chi':
      case 'zh':
      case 'zho':
      case 'chinese':
        return 'Chinese';
      case 'ara':
      case 'ar':
      case 'arabic':
        return 'Arabic';
      case 'und':
      case 'unk':
      case '':
        return ''; // Undefined/Unknown
      default:
        return _capitalize(lang);
    }
  }

  static ParsedTrack parseAudio(AudioTrack? t) {
    if (t == null) return const ParsedTrack(mainTitle: 'Auto');

    String title = t.title?.trim() ?? '';
    final lang = _normalizeLanguage(t.language?.trim() ?? '');

    // 1. Remove release group brackets completely
    title = title.replaceAll(RegExp(r'\[.*?\]'), '').trim();

    // 2. Format: "Japanese / 5.1ch Opus" or "Inner Silence / 5.1ch Opus"
    if (title.contains('/')) {
      final parts = title.split('/');
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

    // 3. Technical Jargon fallback (e.g. "Surround 5.1")
    final lower = title.toLowerCase();
    if (lower == 'surround 5.1' ||
        lower == 'stereo' ||
        lower.contains('opus') ||
        lower.contains('aac') ||
        lower.contains('flac')) {
      return ParsedTrack(
        mainTitle: lang.isEmpty ? 'Audio Track' : lang,
        subTitle: title,
      );
    }

    // 4. Default Fallback
    return ParsedTrack(
      mainTitle: lang.isEmpty ? (title.isEmpty ? 'Audio Track' : title) : lang,
      subTitle: lang.isEmpty || title.toLowerCase() == lang.toLowerCase()
          ? null
          : title,
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

    // 3. Standardize Generic Names
    final lower = title.toLowerCase();
    if (lower.contains('sign') || lower.contains('song')) {
      title = 'Signs & Songs';
    } else if (lower.contains('full') ||
        lower.contains('dialogue') ||
        lower == 'english' ||
        lower == 'japanese') {
      title = 'Full Subtitles';
    }

    // 4. Build Final Strings
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
