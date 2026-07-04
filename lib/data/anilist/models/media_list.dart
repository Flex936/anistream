import 'anime.dart';

class MediaListEntry {
  final int progress;
  final Anime media;

  const MediaListEntry({required this.progress, required this.media});

  factory MediaListEntry.fromJson(Map<String, dynamic> json) => MediaListEntry(
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    media: Anime.fromJson(json['media'] as Map<String, dynamic>),
  );
}

class MediaList {
  final String name;
  final String status;
  final List<MediaListEntry> entries;

  const MediaList({
    required this.name,
    required this.status,
    required this.entries,
  });

  factory MediaList.fromJson(Map<String, dynamic> json) => MediaList(
    name: json['name'] as String? ?? '',
    status: json['status'] as String? ?? '',
    entries: (json['entries'] as List<dynamic>? ?? [])
        .map((e) => MediaListEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
