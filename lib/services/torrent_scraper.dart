// lib/services/torrent_scraper.dart
//
// Torrent data model and mock scraper service.
//
// The real implementation will call the Nyaa.si RSS endpoint from nyaa.go
// (or a future Dart port of it). Swap the body of [fetchTorrents] with the
// real HTTP call when that backend is ready — the model and the UI contract
// stay identical.

// ════════════════════════════════════════════════════════════════════════════
//  Model
// ════════════════════════════════════════════════════════════════════════════

/// A single torrent result, mirroring the [TorrentResult] struct in nyaa.go.
///
/// Field names are intentionally kept identical so the eventual Dart port of
/// the scraper can drop this model in without touching any UI code.
class Torrent {
  final String id;

  /// Release group tag as it appears in the torrent title, e.g. "[SubsPlease]".
  final String releaseGroup;

  /// Video resolution, e.g. "1080p" or "720p".
  final String resolution;

  /// Human-readable file size, e.g. "1.45 GB".
  final String size;

  /// Current seeder count. Used to colour-code the health indicator.
  final int seeders;

  /// Full BitTorrent magnet URI passed to the streaming pipeline.
  final String magnetLink;

  const Torrent({
    required this.id,
    required this.releaseGroup,
    required this.resolution,
    required this.size,
    required this.seeders,
    required this.magnetLink,
  });
}

// ════════════════════════════════════════════════════════════════════════════
//  Service
// ════════════════════════════════════════════════════════════════════════════

/// Mock implementation of the Nyaa.si RSS scraper.
///
/// Returns a pre-ranked list of releases (best → worst, matching the
/// score-sorted output from [nyaa.go]) after a simulated network delay
/// so [FutureBuilder] loading states are clearly visible in development.
class TorrentScraperService {
  // Seed data ordered best → worst, mirroring the scoring heuristics in
  // nyaa.go (SubsPlease 1080p wins on seeder count + quality; MTBB loses
  // on seeders but wins on file size due to AV1 encoding).
  static const List<_ReleaseTemplate> _templates = [
    _ReleaseTemplate('[SubsPlease]', '1080p', '1.45 GB', 842),
    _ReleaseTemplate('[SubsPlease]', '720p', '780 MB', 524),
    _ReleaseTemplate('[Erai-raws]', '1080p', '830 MB', 231),
    _ReleaseTemplate('[MTBB]', '1080p', '615 MB', 87),
  ];

  /// Returns mock torrents for [animeTitle] episode [episodeNumber].
  ///
  /// Simulates ~900 ms of real network + RSS parse latency.
  /// Each call for the same (title, episode) pair returns a fresh list; the
  /// caller is responsible for caching (see [_futureFor] in the screen).
  Future<List<Torrent>> fetchTorrents(
    String animeTitle,
    int episodeNumber,
  ) async {
    await Future.delayed(const Duration(milliseconds: 900));

    final ep = episodeNumber.toString().padLeft(2, '0');

    // Sanitise the title for use in filenames and magnet display-names,
    // mirroring the punctRe / whitespaceRe pipeline in nyaa.go.
    final safeName = animeTitle
        .replaceAll(RegExp(r"[^\w\s\-]"), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');

    return List.generate(_templates.length, (i) {
      final t = _templates[i];
      final filename = '${t.group} $animeTitle - $ep [${t.resolution}].mkv';

      return Torrent(
        id: '$safeName-ep$ep-$i',
        releaseGroup: t.group,
        resolution: t.resolution,
        size: t.size,
        seeders: t.seeders,
        // Placeholder magnet — the real scraper supplies the Nyaa info-hash.
        magnetLink:
            'magnet:?xt=urn:btih:placeholder_${i}_$safeName$ep'
            '&dn=${Uri.encodeComponent(filename)}'
            '&tr=${Uri.encodeComponent("http://nyaa.tracker.wf:7777/announce")}',
      );
    });
  }
}

// ─── Private seed data ────────────────────────────────────────────────────────

/// Immutable descriptor for one mock release group.
class _ReleaseTemplate {
  final String group;
  final String resolution;
  final String size;
  final int seeders;

  const _ReleaseTemplate(this.group, this.resolution, this.size, this.seeders);
}
