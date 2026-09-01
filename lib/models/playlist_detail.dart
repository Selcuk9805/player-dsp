import 'track.dart';

/// A curated (YT Music) playlist fetched from `another-dsp` — distinct from
/// [CustomPlaylist], which is a purely local, user-created list.
class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.title,
    this.author,
    this.thumbnailUrl,
    required this.tracks,
  });

  final String id;
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final List<Track> tracks;

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) {
    final thumb = json['thumbnailUrl'] as String?;
    return PlaylistDetail(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      thumbnailUrl: thumb,
      tracks: (json['tracks'] as List)
          .cast<Map<String, dynamic>>()
          .map((t) => Track.fromCatalogJson(t, fallbackThumbnailUrl: thumb))
          .toList(),
    );
  }
}
