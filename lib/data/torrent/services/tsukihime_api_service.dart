import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/tsukihime_models.dart';

class TsukihimeException implements Exception {
  final String message;
  final int? statusCode;
  const TsukihimeException(this.message, {this.statusCode});
  @override
  String toString() => 'TsukihimeException($statusCode): $message';
}

class TsukihimeApiService {
  static const String _baseUrl = 'https://api.tsukihime.org/v1';
  final http.Client _client;
  TsukihimeApiService({http.Client? client})
    : _client = client ?? http.Client();
  Future<http.Response> _get(String path, {Map<String, String>? query}) {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    return _client.get(uri).timeout(const Duration(seconds: 10));
  }

  Future<List<TsukihimeTorrentWire>> _getTorrentEnvelope(
    String path, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _get(
      path,
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    if (response.statusCode != 200) {
      throw TsukihimeException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawResults = data['results'] as List<dynamic>? ?? const [];
    return rawResults
        .map((r) => TsukihimeTorrentWire.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // TODO: cache these ids per session to lessen requests (aka if someones bingewatches the show only run this once)
  Future<int?> resolveInternalId(int anilistId) async {
    final response = await _get('/animes/anilist/$anilistId');
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw TsukihimeException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['id'] as num?)?.toInt();
  }

  Future<List<TsukihimeTorrentWire>> getSeriesTorrents(
    int internalId, {
    int limit = 50,
    int offset = 0,
  }) =>
      _getTorrentEnvelope('/animes/$internalId', limit: limit, offset: offset);
  Future<List<TsukihimeTorrentWire>> getEpisodeTorrents(
    int internalId,
    int episodeNumber,
  ) => _getTorrentEnvelope('/animes/$internalId/episodes/$episodeNumber');

  void dispose() {
    _client.close();
  }
}
