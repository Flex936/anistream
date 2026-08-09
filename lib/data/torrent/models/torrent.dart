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

  /// Built on demand instead of at construction time — a single search can
  /// produce 50-300 scored `Torrent`s, but the UI only ever needs a magnet
  /// link for the one the user actually hands to libtorrent, so building
  /// and percent-encoding tracker URLs for every candidate up front would
  /// be mostly wasted work.
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
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Torrent && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Torrent($title, res: $resolution, seeders: $seeders, score: $score)';
}
