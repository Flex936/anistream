final RegExp _brTagRegex = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _anyTagRegex = RegExp(r'<[^>]+>');
final RegExp _multiNewlineRegex = RegExp(r'\n{3,}');

/// Strips AniList's HTML description markup to plain text; [preserveLineBreaks]
/// keeps `<br>` as newlines for multi-paragraph synopses.
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