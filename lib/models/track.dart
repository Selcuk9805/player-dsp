/// Mirrors `another-dsp`'s `CatalogItem` schema (app/models/catalog_schemas.py).
/// Only `type == "song"` items are directly playable — album/artist/playlist
/// items are browsable containers, modeled separately once those screens land.
class Track {
  const Track({
    required this.videoId,
    required this.title,
    this.artist,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  final String videoId;
  final String title;
  final String? artist;
  final String? thumbnailUrl;
  final int? durationSeconds;

  Duration? get duration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);

  Track copyWith({
    String? videoId,
    String? title,
    String? artist,
    String? thumbnailUrl,
    int? durationSeconds,
  }) =>
      Track(
        videoId: videoId ?? this.videoId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );

  factory Track.fromCatalogJson(
    Map<String, dynamic> json, {
    String? fallbackThumbnailUrl,
    String? fallbackArtist,
  }) {
    return Track(
      videoId: json['id'] as String,
      title: json['title'] as String,
      artist: (json['subtitle'] as String?) ?? fallbackArtist,
      thumbnailUrl: (json['thumbnailUrl'] as String?) ?? fallbackThumbnailUrl,
      durationSeconds: json['durationSeconds'] as int?,
    );
  }

  /// Persistence shape used by [StorageService] for favorites/playlists —
  /// distinct field names from [fromCatalogJson] since this is our own
  /// on-disk format, not a mirror of a backend response.
  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnailUrl': thumbnailUrl,
    'durationSeconds': durationSeconds,
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    videoId: json['videoId'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    durationSeconds: json['durationSeconds'] as int?,
  );

  @override
  bool operator ==(Object other) => other is Track && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}
