import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/album_detail.dart';
import '../models/artist_detail.dart';
import '../models/catalog_item.dart';
import '../models/playlist_detail.dart';
import '../models/track.dart';
import 'storage_service.dart';

/// Thrown when `another-dsp` can't be reached at all (DNS/connect failure,
/// timeout) — screens use this to distinguish "server down" from "server
/// replied with an error" (which surfaces as a plain [http.ClientException]
/// message from the response body instead).
class CatalogUnreachableException implements Exception {
  CatalogUnreachableException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client for `another-dsp`'s `/api/catalog/*` endpoints. The catalog is
/// intentionally not cached client-side beyond what the backend already does
/// — see the approved plan's "sunucu erişilemez" note: when the backend is
/// down, catalog screens are meant to show that clearly, not silently fall
/// back to stale/local data.
class CatalogService {
  CatalogService(this._storage, {http.Client? client})
    : _client = client ?? http.Client();

  final StorageService _storage;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${_storage.dspServerUrl}$path')
          .replace(queryParameters: query);

  Future<dynamic> _getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw CatalogUnreachableException('Sunucuya ulaşılamıyor: $e');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Sunucu hatası (${response.statusCode}): ${response.body}',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<CatalogItem>> search(String query, {String? filter}) async {
    final json = await _getJson(
      _uri('/api/catalog/search', {
        'q': query,
        'filter': ?filter,
      }),
    );
    final results = (json['results'] as List).cast<Map<String, dynamic>>();
    return results.map(CatalogItem.fromJson).toList();
  }

  Future<ArtistDetail> getArtist(String artistId) async {
    final json = await _getJson(_uri('/api/catalog/artist/$artistId'));
    return ArtistDetail.fromJson(json as Map<String, dynamic>);
  }

  Future<AlbumDetail> getAlbum(String albumId) async {
    final json = await _getJson(_uri('/api/catalog/album/$albumId'));
    return AlbumDetail.fromJson(json as Map<String, dynamic>);
  }

  Future<PlaylistDetail> getPlaylist(String playlistId) async {
    final json = await _getJson(_uri('/api/catalog/playlist/$playlistId'));
    return PlaylistDetail.fromJson(json as Map<String, dynamic>);
  }

  Future<List<Track>> watchPlaylist(String videoId) async {
    final json = await _getJson(_uri('/api/catalog/watch/$videoId'));
    final tracks = (json['tracks'] as List).cast<Map<String, dynamic>>();
    return tracks.map(Track.fromCatalogJson).toList();
  }

  Future<({List<CatalogItem> playlists, List<CatalogItem> artists})> charts({
    String country = 'TR',
  }) async {
    final json = await _getJson(
      _uri('/api/catalog/charts', {'country': country}),
    );
    final playlists = (json['trendingPlaylists'] as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList();
    final artists = (json['trendingArtists'] as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList();
    return (playlists: playlists, artists: artists);
  }

  void dispose() => _client.close();
}
