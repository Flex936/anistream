import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import 'bencode.dart';

class TrackerScrapeStats {
  final int seeders;
  final int leechers;
  final int completed;

  const TrackerScrapeStats({
    required this.seeders,
    required this.leechers,
    required this.completed,
  });
}

/// Queries BitTorrent trackers directly for live seeder/leecher counts,
/// keyed purely by info hash — see the class doc in torrent_scraper_service.dart's
/// enrichment step for why this replaced a title-search-based approach.
class TrackerScrapeService {
  final http.Client _client;
  final Random _random = Random();

  TrackerScrapeService(this._client);

  // Both answer HTTP scrape on the same host:port their announce URL
  // uses — see torrent.dart's own _trackers list.
  static const List<String> _httpTrackers = [
    'http://nyaa.tracker.wf:7777/scrape',
    'http://tracker.opentrackr.org:1337/scrape',
  ];

  // No known HTTP scrape endpoint for these — UDP only.
  static const List<({String host, int port})> _udpTrackers = [
    (host: 'exodus.desync.com', port: 6969),
    (host: 'open.stealth.si', port: 80),
    (host: 'tracker.torrent.eu.org', port: 451),
  ];

  /// Returns live stats for as many of [hashesHex] as any tracker knows
  /// about. A missing entry just means no tracker reported that hash —
  /// not necessarily an error.
  Future<Map<String, TrackerScrapeStats>> scrape(List<String> hashesHex) async {
    if (hashesHex.isEmpty) return {};
    final hashes = hashesHex.map((h) => h.toLowerCase()).toList();

    final results = await Future.wait([
      ..._httpTrackers.map((url) => _scrapeHttp(url, hashes)),
      ..._udpTrackers.map((t) => _scrapeUdp(t.host, t.port, hashes)),
    ]);

    // Different trackers only know about peers that announced to them —
    // taking the max across trackers avoids undercounting a real swarm.
    final merged = <String, TrackerScrapeStats>{};
    for (final trackerResult in results) {
      for (final entry in trackerResult.entries) {
        final existing = merged[entry.key];
        if (existing == null || entry.value.seeders > existing.seeders) {
          merged[entry.key] = entry.value;
        }
      }
    }
    return merged;
  }

  // HTTP scrape.

  Future<Map<String, TrackerScrapeStats>> _scrapeHttp(
    String announceUrl,
    List<String> hashesHex,
  ) async {
    final scrapeUrl = _scrapeUrlFor(announceUrl);
    if (scrapeUrl == null) return {};

    try {
      final uri = _buildHttpScrapeUri(
        scrapeUrl,
        hashesHex.map(hexDecode).toList(),
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return {};
      return _parseHttpScrapeBody(response.bodyBytes);
    } catch (e) {
      AppLogger.w(
        'TrackerScrapeService',
        'HTTP scrape failed for $announceUrl: $e',
      );
      return {};
    }
  }

  /// Per the scrape convention: an announce URL ending in "/announce"
  /// supports scraping by swapping that segment for "/scrape".
  String? _scrapeUrlFor(String announceUrl) {
    final uri = Uri.parse(announceUrl);
    final segments = uri.pathSegments;
    if (segments.isEmpty || segments.last != 'announce') return null;
    final scrapeSegments = [
      ...segments.sublist(0, segments.length - 1),
      'scrape',
    ];
    return uri.replace(pathSegments: scrapeSegments).toString();
  }

  Uri _buildHttpScrapeUri(String scrapeUrl, List<Uint8List> hashes) {
    final buffer = StringBuffer(scrapeUrl)
      ..write(scrapeUrl.contains('?') ? '&' : '?');
    buffer.writeAll(
      hashes.map((h) => 'info_hash=${_percentEncodeBytes(h)}'),
      '&',
    );
    return Uri.parse(buffer.toString());
  }

  /// info_hash must be the RAW 20 bytes, percent-encoded — not the hex
  /// string. Dart's own Uri.encodeComponent UTF-8-encodes text first,
  /// which mangles any raw byte >= 0x80 into a multi-byte sequence
  /// instead of one %XX per byte, so this is hand-rolled instead.
  /// Percent-encoding every byte unconditionally is always valid per the
  /// URI spec and simpler than only encoding the ones that strictly need it.
  String _percentEncodeBytes(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write('%');
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// A reply looks like:
  /// d5:filesd20:(raw hash)d8:completei5e10:downloadedi12e10:incompletei1eeee
  /// "complete" is what every torrent client calls seeders.
  Map<String, TrackerScrapeStats> _parseHttpScrapeBody(Uint8List body) {
    final decoded = BencodeReader(body).readValue() as Map<String, dynamic>;
    final files = decoded['files'] as Map<String, dynamic>? ?? const {};

    final result = <String, TrackerScrapeStats>{};
    for (final entry in files.entries) {
      final hashHex = hexEncode(entry.key.codeUnits);
      final stats = entry.value as Map<String, dynamic>;
      result[hashHex] = TrackerScrapeStats(
        seeders: stats['complete'] as int? ?? 0,
        leechers: stats['incomplete'] as int? ?? 0,
        completed: stats['downloaded'] as int? ?? 0,
      );
    }
    return result;
  }

  // UDP scrape (BEP 0015).

  static const int _kProtocolId =
      0x41727101980; // fixed magic value the spec requires
  static const int _kActionConnect = 0;
  static const int _kActionScrape = 2;

  Future<Map<String, TrackerScrapeStats>> _scrapeUdp(
    String host,
    int port,
    List<String> hashesHex,
  ) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final packetController = StreamController<Uint8List>.broadcast();

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      if (addresses.isEmpty) return {};
      final address = addresses.first;

      // Exactly one listen() for this socket's whole lifetime — see the
      // class doc for why calling it per-retry throws. Every subsequent
      // "wait for the next packet" reads from packetController's
      // broadcast stream instead, which can be subscribed to any number
      // of times. onError is required here: an unhandled error on a raw
      // socket's event stream becomes an uncaught, zone-level crash if
      // nothing is listening for it — that's what escaped this function's
      // own try/catch before this fix.
      subscription = socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket!.receive();
            if (datagram != null) packetController.add(datagram.data);
          }
        },
        onError: (Object e) {
          AppLogger.w(
            'TrackerScrapeService',
            'Socket error for $host:$port: $e',
          );
        },
      );

      final connectTxId = _random.nextInt(0x7fffffff);
      final connectResp = await _sendWithRetries(
        socket: socket,
        address: address,
        port: port,
        request: _buildConnectRequest(connectTxId),
        expectedTransactionId: connectTxId,
        packets: packetController.stream,
      );
      if (connectResp == null || connectResp.length < 16) return {};

      final connectView = ByteData.sublistView(connectResp);
      if (connectView.getUint32(0) != _kActionConnect) return {};
      final connectionId = connectView.getUint64(8);

      final scrapeTxId = _random.nextInt(0x7fffffff);
      final hashBytes = hashesHex.map(hexDecode).toList();
      final scrapeResp = await _sendWithRetries(
        socket: socket,
        address: address,
        port: port,
        request: _buildScrapeRequest(connectionId, scrapeTxId, hashBytes),
        expectedTransactionId: scrapeTxId,
        packets: packetController.stream,
      );
      if (scrapeResp == null) return {};

      return _parseUdpScrapeResponse(scrapeResp, hashesHex);
    } catch (e) {
      AppLogger.w(
        'TrackerScrapeService',
        'UDP scrape failed for $host:$port: $e',
      );
      return {};
    } finally {
      await subscription?.cancel();
      await packetController.close();
      socket?.close();
    }
  }

  Uint8List _buildConnectRequest(int transactionId) {
    final data = ByteData(16);
    data.setUint64(0, _kProtocolId);
    data.setUint32(8, _kActionConnect);
    data.setUint32(12, transactionId);
    return data.buffer.asUint8List();
  }

  Uint8List _buildScrapeRequest(
    int connectionId,
    int transactionId,
    List<Uint8List> hashes,
  ) {
    final bytes = Uint8List(16 + 20 * hashes.length);
    final header = ByteData.sublistView(bytes, 0, 16);
    header.setUint64(0, connectionId);
    header.setUint32(8, _kActionScrape);
    header.setUint32(12, transactionId);

    var offset = 16;
    for (final hash in hashes) {
      bytes.setRange(offset, offset + 20, hash);
      offset += 20;
    }
    return bytes;
  }

  /// Sends [request] up to 3 times, waiting for a reply whose transaction
  /// ID matches [expectedTransactionId] each time. Matching on ID (rather
  /// than just "the next packet off the stream") is what correctly
  /// discards a late reply to attempt 1 if it arrives after attempt 2 has
  /// already gone out, instead of misattributing it.
  Future<Uint8List?> _sendWithRetries({
    required RawDatagramSocket socket,
    required InternetAddress address,
    required int port,
    required Uint8List request,
    required int expectedTransactionId,
    required Stream<Uint8List> packets,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      socket.send(request, address, port);
      final response = await _awaitMatchingPacket(
        packets,
        expectedTransactionId,
        const Duration(seconds: 3),
      );
      if (response != null) return response;
    }
    return null;
  }

  Future<Uint8List?> _awaitMatchingPacket(
    Stream<Uint8List> packets,
    int expectedTransactionId,
    Duration timeout,
  ) async {
    try {
      return await packets
          .firstWhere(
            (data) =>
                data.length >= 8 &&
                ByteData.sublistView(data).getUint32(4) ==
                    expectedTransactionId,
          )
          .timeout(timeout);
    } on TimeoutException {
      return null;
    } on StateError {
      return null; // stream closed with no match — e.g. during teardown
    }
  }

  Map<String, TrackerScrapeStats> _parseUdpScrapeResponse(
    Uint8List data,
    List<String> hashesInOrder, // response order matches request order
  ) {
    if (data.length < 8) return {};
    final view = ByteData.sublistView(data);

    final result = <String, TrackerScrapeStats>{};
    var offset = 8;
    for (final hashHex in hashesInOrder) {
      if (offset + 12 > data.length) break;
      result[hashHex] = TrackerScrapeStats(
        seeders: view.getUint32(offset),
        completed: view.getUint32(offset + 4),
        leechers: view.getUint32(offset + 8),
      );
      offset += 12;
    }
    return result;
  }
}
