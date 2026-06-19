class Torrent {
  final String id;
  final String title;
  final String releaseGroup;
  final String resolution;
  final String size;
  final int seeders;
  final String magnetLink;
  final double score;
  final bool isBatch;

  const Torrent({
    required this.id,
    required this.title,
    required this.releaseGroup,
    required this.resolution,
    required this.size,
    required this.seeders,
    required this.magnetLink,
    this.isBatch = false,
    this.score = 0.0,
  });
}
