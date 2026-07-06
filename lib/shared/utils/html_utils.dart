final RegExp _brTagRegex = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _anyTagRegex = RegExp(r'<[^>]+>');
final RegExp _multiNewlineRegex = RegExp(r'\n{3,}');

/// Strips AniList's HTML-flavored description markup down to plain text.
/// Consolidates the two divergent `_stripHtml` copies that used to live in
/// `watchlist_cards.dart` and `hero_banner.dart`.
///
/// [preserveLineBreaks]: true for the details hero banner's multi-paragraph
/// synopsis (`<br>` → `\n`); false for card/list summaries that collapse to
/// one line.
String stripAnilistHtml(String? html, {bool preserveLineBreaks = false}) {
  if (html == null || html.isEmpty) return 'No synopsis available.';
  var text = html;
  if (preserveLineBreaks) {
    text = text.replaceAll(_brTagRegex, '\n');
  }
  text = text.replaceAll(_anyTagRegex, '');
  if (preserveLineBreaks) {
    text = text.replaceAll(_multiNewlineRegex, '\n\n');
  }
  return text.trim();
}
