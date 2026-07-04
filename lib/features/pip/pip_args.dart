import 'dart:convert';

class PipArgs {
  final bool isPip;
  final String? streamUrl;
  final String? title;
  final int? episode;
  final int positionMs;
  final String? mainWindowId;

  const PipArgs.main()
    : isPip = false,
      streamUrl = null,
      title = null,
      episode = null,
      positionMs = 0,
      mainWindowId = null;

  const PipArgs.pip({
    required this.streamUrl,
    required this.title,
    required this.episode,
    required this.positionMs,
    required this.mainWindowId,
  }) : isPip = true;

  static PipArgs fromRaw(String? raw) {
    // Prevent crashes if the argument is missing or malformed
    if (raw == null || raw.trim().isEmpty || raw == 'null') {
      return const PipArgs.main();
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PipArgs.pip(
        streamUrl: map['streamUrl'] as String?,
        title: map['title'] as String?,
        episode: map['episode'] as int?,
        positionMs: map['positionMs'] as int? ?? 0,
        mainWindowId: map['mainWindowId'] as String?,
      );
    } catch (_) {
      return const PipArgs.main();
    }
  }

  String toRaw() => jsonEncode({
    'streamUrl': streamUrl,
    'title': title,
    'episode': episode,
    'positionMs': positionMs,
    'mainWindowId': mainWindowId,
  });
}
