import 'track.dart';

class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.title,
    this.artist,
    this.artistId,
    this.thumbnailUrl,
    this.year,
    required this.tracks,
  });

  final String id;
  final String title;
  final String? artist;
  final String? artistId;
  final String? thumbnailUrl;
  final String? year;
  final List<Track> tracks;

  factory AlbumDetail.fromJson(Map<String, dynamic> json) {
    final thumb = json['thumbnailUrl'] as String?;
    final artist = json['artist'] as String?;
    return AlbumDetail(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: artist,
      artistId: json['artistId'] as String?,
      thumbnailUrl: thumb,
      year: json['year'] as String?,
      tracks: (json['tracks'] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (t) => Track.fromCatalogJson(
              t,
              fallbackThumbnailUrl: thumb,
              fallbackArtist: artist,
            ),
          )
          .toList(),
    );
  }
}
