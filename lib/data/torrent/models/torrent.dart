import 'package:flutter/foundation.dart';

/// Immutable result of scoring a single Nyaa RSS item against the
/// requested anime + episode.
@immutable
class Torrent {
  final String id;
  final String title;
  final String releaseGroup;
  final String resolution;
  final String size;
  final int seeders;
  final double score;
  final bool isBatch;

  const Torrent({
    required this.id,
    required this.title,
    required this.releaseGroup,
    required this.resolution,
    required this.size,
    required this.seeders,
    this.isBatch = false,
    this.score = 0.0,
  });

  static const List<String> _trackers = [
    'http://nyaa.tracker.wf:7777/announce',
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://exodus.desync.com:6969/announce',
  ];

  /// Built on demand instead of at construction time.
  ///
  /// A single search can produce 50-300 scored `Torrent`s, but the UI only
  /// ever needs a magnet link for the *one* the user actually hands to
  /// libtorrent. The old code built and percent-encoded 3 tracker URLs for
  /// every single candidate up front, even though ~99% of that work was
  /// thrown away. Same trackers, same encoding, same final string — just
  /// computed only when something actually asks for it.
  String get magnetLink {
    final buffer = StringBuffer()
      ..write('magnet:?xt=urn:btih:')
      ..write(id)
      ..write('&dn=')
      ..write(Uri.encodeComponent(title));
    for (final tracker in _trackers) {
      buffer
        ..write('&tr=')
        ..write(Uri.encodeComponent(tracker));
    }
    return buffer.toString();
  }

  /// Two `Torrent`s are the same release if they share an infoHash.
  /// (Additive — nothing in the current scraper relies on this, it still
  /// dedupes via a `Set<String>` of ids, but it's a reasonable default for
  /// a model class and costs nothing. Drop it if you'd rather keep
  /// identity equality.)
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Torrent && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Torrent($title, res: $resolution, seeders: $seeders, score: $score)';
}
