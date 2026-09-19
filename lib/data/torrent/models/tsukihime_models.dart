import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../services/torrent_parser.dart';
import 'torrent.dart';

class TsukihimeTorrentWire {
  final int id;
  final String btih;
  final String title;
  final int? totalSize;
  final int? fileCount;
  final bool? isMovie;
  final int? airStatus;
  final int? episodeNo;
  final String? groupName;
  final bool? groupIsFansub;
  final String? state;
  final int? nyaaId;
  final int? sourceDate;

  const TsukihimeTorrentWire({
    required this.id,
    required this.btih,
    required this.title,
    this.totalSize,
    this.fileCount,
    this.isMovie,
    this.airStatus,
    this.episodeNo,
    this.groupIsFansub,
    this.groupName,
    this.nyaaId,
    this.sourceDate,
    this.state,
  });

  factory TsukihimeTorrentWire.fromJson(Map<String, dynamic> json) {
    final group = json["group"] as Map<String, dynamic>?;
    return TsukihimeTorrentWire(
      id: (json['id'] as num?)?.toInt() ?? 0,
      btih: json['btih'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      totalSize: (json['totalsize'] as num?)?.toInt(),
      fileCount: (json['filecount'] as num?)?.toInt(),
      isMovie: (json["is_movie"] as num?)?.toInt() == 1,
      airStatus: (json['air_status'] as num?)
          ?.toInt(), //0=Unknown, 1=Airing, 2=Finished, 3=Not Aired
      episodeNo: (json["episode_no"] as num?)?.toInt(),
      groupName: group?["name"] as String?,
      groupIsFansub: group == null
          ? null
          : (group["is_fansub"] as num?)?.toInt() == 1,
      state: (json["state"] as String?),
      nyaaId: (json["nyaa_id"] as num?)?.toInt(),
      sourceDate: (json["source_date"] as num?)?.toInt(),
    );
  }
}

extension TsukihimeTorrentMapping on TsukihimeTorrentWire {
  Torrent toAppTorrent() {
    final meta = TorrentParser.parse(title);
    final tl = title.toLowerCase();
    double score = 0;
    if (meta.resolution == "1080p") {
      score += 20;
    } else if (meta.resolution == "720p") {
      score += 10;
    }
    if (tl.contains('av1')) {
      score += 30;
    } else if (tl.contains("hevc") || tl.contains("x265")) {
      score += 20;
    }
    if (episodeNo == null) score += 5;
    return Torrent(
      id: btih,
      title: title,
      releaseGroup: groupName ?? meta.releaseGroup,
      resolution: meta.resolution,
      size: formatBytes(totalSize ?? 0),
      seeders: 0,
      score: score,
      isBatch: episodeNo == null,
    );
  }
}
