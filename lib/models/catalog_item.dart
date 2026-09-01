import 'track.dart';

/// A single catalog search/browse result of any kind — song, album, artist,
/// or playlist. Kept as one shape (rather than a union of typed models) since
/// search results are heterogeneous and the UI just needs to know how to
/// route a tap: play (song) vs. navigate to a detail screen (the rest).
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  final String id;
  final String type; // "song" | "album" | "artist" | "playlist"
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final int? durationSeconds;

  bool get isSong => type == 'song';

  /// Only meaningful when [isSong] — `id` is the track's videoId in that case.
  Track toTrack() => Track(
    videoId: id,
    title: title,
    artist: subtitle,
    thumbnailUrl: thumbnailUrl,
    durationSeconds: durationSeconds,
  );

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    return CatalogItem(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
    );
  }
}
