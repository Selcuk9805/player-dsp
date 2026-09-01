import 'catalog_item.dart';
import 'track.dart';

class ArtistDetail {
  const ArtistDetail({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    required this.topSongs,
    required this.albums,
    required this.relatedArtists,
  });

  final String id;
  final String name;
  final String? thumbnailUrl;
  final List<Track> topSongs;
  final List<CatalogItem> albums;
  final List<CatalogItem> relatedArtists;

  factory ArtistDetail.fromJson(Map<String, dynamic> json) => ArtistDetail(
    id: json['id'] as String,
    name: json['name'] as String,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    topSongs: (json['topSongs'] as List)
        .cast<Map<String, dynamic>>()
        .map(Track.fromCatalogJson)
        .toList(),
    albums: (json['albums'] as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList(),
    relatedArtists: (json['relatedArtists'] as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList(),
  );
}
