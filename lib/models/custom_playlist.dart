import 'track.dart';

/// A user-created (or saved-from-curated) local playlist — favorites/
/// playlists never touch `another-dsp`, they're SharedPreferences-backed
/// via `StorageService`.
class CustomPlaylist {
  const CustomPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.tracks,
    this.sourcePlaylistId,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<Track> tracks;

  /// Set when this playlist was saved from a curated (YT Music) playlist via
  /// `LibraryManager.toggleSavedPlaylist` — lets the Playlist screen know
  /// whether "Kaydet" should show as already-saved for that source playlist,
  /// without matching on name (which curated playlists can share).
  final String? sourcePlaylistId;

  CustomPlaylist copyWith({String? name, List<Track>? tracks}) =>
      CustomPlaylist(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        tracks: tracks ?? this.tracks,
        sourcePlaylistId: sourcePlaylistId,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'sourcePlaylistId': sourcePlaylistId,
  };

  factory CustomPlaylist.fromJson(Map<String, dynamic> json) => CustomPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    tracks: (json['tracks'] as List)
        .cast<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList(),
    sourcePlaylistId: json['sourcePlaylistId'] as String?,
  );
}
