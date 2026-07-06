import 'dart:math' as math;
import 'package:xml/xml.dart';
import '../models/torrent.dart';
import 'torrent_parser.dart';

typedef ScoringContext = ({
  String animeTitleLower,
  bool hasFinalSeason,
  bool isMovie,
  bool isOvaFormat,
  int targetSeason,
  int episodeNumber,
  int? totalEpisodes,
  bool batchMode,
});

typedef RawItemFields = ({
  String title,
  String? infoHash,
  String size,
  int seeders,
  bool isTrusted,
});

/// Splits the old 200-line `_scoreItem` monolith into six independent,
/// named steps. No scoring math was changed — this is a pure reorganization
/// so a future change to (say) the size curve doesn't require reading the
/// whole function to find it.
abstract final class TorrentScoringEngine {
  static Torrent? score(XmlElement item, ScoringContext ctx) {
    final fields = _extractItemFields(item);
    if (fields.infoHash == null || fields.infoHash!.isEmpty) return null;
    if (fields.seeders == 0) return null;

    final rawTitle = fields.title;
    final meta = TorrentParser.parse(rawTitle);
    final tl = rawTitle.toLowerCase();

    double? score = _scoreBatchAndSeason(meta, ctx, 100.0);
    if (score == null) return null; // rejected by batch/season/episode filter

    score = _scoreFinalSeasonTag(tl, ctx, score);
    score = _scoreFormatTags(tl, meta, ctx, score);
    score = _scoreCodecAndResolution(tl, meta, score);
    score = _scoreTrustAndSeeders(fields, score);
    score = _scoreSizeHeuristics(fields.size, meta, ctx, score);

    return Torrent(
      id: fields.infoHash!,
      title: rawTitle,
      releaseGroup: meta.releaseGroup,
      resolution: meta.resolution,
      size: fields.size,
      seeders: fields.seeders,
      score: score,
      isBatch: meta.isBatch,
    );
  }

  static RawItemFields _extractItemFields(XmlElement item) {
    var title = '';
    String? infoHash;
    var size = '0 MiB';
    var seeders = 0;
    var isTrusted = false;
    var hasTitle = false,
        hasInfoHash = false,
        hasSize = false,
        hasSeeders = false,
        hasTrusted = false;

    for (final child in item.childElements) {
      switch (child.name.qualified) {
        case 'title':
          if (!hasTitle) {
            title = child.innerText;
            hasTitle = true;
          }
        case 'nyaa:infoHash':
          if (!hasInfoHash) {
            infoHash = child.innerText;
            hasInfoHash = true;
          }
        case 'nyaa:size':
          if (!hasSize) {
            size = child.innerText;
            hasSize = true;
          }
        case 'nyaa:seeders':
          if (!hasSeeders) {
            seeders = int.tryParse(child.innerText) ?? 0;
            hasSeeders = true;
          }
        case 'nyaa:trusted':
          if (!hasTrusted) {
            isTrusted = child.innerText.toLowerCase() == 'yes';
            hasTrusted = true;
          }
      }
    }
    return (
      title: title,
      infoHash: infoHash,
      size: size,
      seeders: seeders,
      isTrusted: isTrusted,
    );
  }

  /// Returns `null` to signal outright rejection; otherwise the running
  /// score with batch/season adjustments applied.
  static double? _scoreBatchAndSeason(
    TorrentMetadata meta,
    ScoringContext ctx,
    double score,
  ) {
    if (ctx.batchMode) {
      if (!meta.isBatch) return null;
      if (meta.season != ctx.targetSeason) return null;
      score += 100;
      if (meta.batchStart != -1 && meta.batchEnd != -1) {
        if (meta.batchStart <= 1 &&
            ctx.totalEpisodes != null &&
            meta.batchEnd >= ctx.totalEpisodes!) {
          score += 20;
        } else if (meta.batchStart > ctx.episodeNumber ||
            meta.batchEnd < ctx.episodeNumber) {
          return null;
        }
      }
      return score;
    }

    if (meta.isBatch) score -= 150;
    score += meta.season == ctx.targetSeason ? 100 : -100;

    if (!ctx.isMovie) {
      if (meta.episode != -1 && meta.episode != ctx.episodeNumber) return null;
    } else {
      if (meta.episode != -1 && meta.episode != 1) return null;
    }
    return score;
  }

  static double _scoreFinalSeasonTag(
    String tl,
    ScoringContext ctx,
    double score,
  ) {
    final torrentFinal = tl.contains('final season');
    if (ctx.hasFinalSeason && torrentFinal) return score + 100;
    if (!ctx.hasFinalSeason && torrentFinal) return score - 100;
    return score;
  }

  static double _scoreFormatTags(
    String tl,
    TorrentMetadata meta,
    ScoringContext ctx,
    double score,
  ) {
    for (final tag in const ['ova', 'ona', 'oad', 'special']) {
      if (!ctx.isOvaFormat &&
          !ctx.animeTitleLower.contains(tag) &&
          tl.contains(tag)) {
        score -= 100;
      } else if (ctx.isOvaFormat && tl.contains(tag)) {
        score += 50;
      }
    }
    if (!ctx.isMovie && tl.contains('movie')) {
      score -= 100;
    } else if (ctx.isMovie &&
        (tl.contains('movie') ||
            tl.contains('gekijouban') ||
            tl.contains('film'))) {
      score += 50;
    }
    return score;
  }

  static double _scoreCodecAndResolution(
    String tl,
    TorrentMetadata meta,
    double score,
  ) {
    if (meta.resolution == '1080p') {
      score += 20;
    } else if (meta.resolution == '720p') {
      score += 10;
    }
    if (tl.contains('av1')) {
      score += 30;
    } else if (tl.contains('hevc') ||
        tl.contains('x265') ||
        tl.contains('h.265')) {
      score += 20;
    } else if (tl.contains('avc') ||
        tl.contains('x264') ||
        tl.contains('h.264')) {
      score += 5;
    }
    if (tl.contains('10bit') || tl.contains('10-bit')) score += 15;
    if (tl.contains('opus')) score += 15;
    if (tl.contains('webrip')) {
      score += 10;
    } else if (tl.contains('web-dl') || tl.contains('webdl')) {
      score += 5;
    }
    return score;
  }

  static double _scoreTrustAndSeeders(RawItemFields fields, double score) {
    if (fields.isTrusted) score += 30;
    return score + (math.log(fields.seeders + 1) * 5).clamp(0, 50);
  }

  static double _scoreSizeHeuristics(
    String sizeStr,
    TorrentMetadata meta,
    ScoringContext ctx,
    double score,
  ) {
    final sizeMB = _parseSizeToMB(sizeStr);
    if (sizeMB <= 0) return score;

    double avgEpSizeMB = sizeMB;
    if (meta.isBatch) {
      int epCount;
      if (meta.batchStart != -1 &&
          meta.batchEnd != -1 &&
          meta.batchEnd >= meta.batchStart) {
        epCount = (meta.batchEnd - meta.batchStart) + 1;
      } else if (ctx.totalEpisodes != null && ctx.totalEpisodes! > 0) {
        epCount = ctx.totalEpisodes!;
      } else {
        epCount = 12;
      }
      avgEpSizeMB = sizeMB / epCount;
    }

    if (ctx.isMovie) {
      if (avgEpSizeMB < 800) {
        score -= 30;
      } else if (avgEpSizeMB >= 1500 && avgEpSizeMB <= 6000) {
        score += 30;
      } else if (avgEpSizeMB > 10000) {
        score -= 40;
      }
    } else {
      if (avgEpSizeMB < 150) {
        score -= 30;
      } else if (avgEpSizeMB >= 250 && avgEpSizeMB <= 1200) {
        score += 30;
      } else if (avgEpSizeMB >= 150 && avgEpSizeMB < 250) {
        score += 10;
      } else if (avgEpSizeMB > 1200 && avgEpSizeMB <= 2500) {
        score += 10;
      } else if (avgEpSizeMB > 2500) {
        score -= 30;
      }
    }
    return score;
  }

  static double _parseSizeToMB(String sizeStr) {
    final lower = sizeStr.toLowerCase().trim();
    final match = RegExp(r'([\d.]+)\s*([kmg]i?b)').firstMatch(lower);
    if (match == null) return 0.0;
    final value = double.tryParse(match.group(1)!) ?? 0.0;
    return switch (match.group(2)!) {
      final u when u.contains('g') => value * 1024,
      final u when u.contains('m') => value,
      final u when u.contains('k') => value / 1024,
      _ => 0.0,
    };
  }
}
