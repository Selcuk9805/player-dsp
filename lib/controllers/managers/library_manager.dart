import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/custom_playlist.dart';
import '../../models/track.dart';
import '../../services/storage_service.dart';

/// Favorites + user-created playlists. Purely local (SharedPreferences via
/// [StorageService]) — never touches `another-dsp`. Loads synchronously from
/// whatever's already on disk at construction; every mutation persists
/// immediately.
class LibraryManager extends ChangeNotifier {
  LibraryManager(this._storage)
    : _favorites = _storage.getFavorites(),
      _playlists = _storage.getPlaylists();

  final StorageService _storage;
  final List<Track> _favorites;
  final List<CustomPlaylist> _playlists;

  List<Track> get favorites => List.unmodifiable(_favorites);
  List<CustomPlaylist> get playlists => List.unmodifiable(_playlists);

  bool isFavorite(Track track) => _favorites.contains(track);

  Future<void> toggleFavorite(Track track) async {
    if (!_favorites.remove(track)) {
      _favorites.add(track);
    }
    await _storage.saveFavorites(_favorites);
    notifyListeners();
  }

  CustomPlaylist createPlaylist(String name) {
    final playlist = CustomPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
      tracks: const [],
    );
    _playlists.add(playlist);
    unawaited(_storage.savePlaylists(_playlists));
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    _playlists[index] = _playlists[index].copyWith(name: newName);
    await _storage.savePlaylists(_playlists);
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((p) => p.id == playlistId);
    await _storage.savePlaylists(_playlists);
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    final existing = _playlists[index];
    if (existing.tracks.contains(track)) return;
    _playlists[index] = existing.copyWith(tracks: [...existing.tracks, track]);
    await _storage.savePlaylists(_playlists);
    notifyListeners();
  }

  /// Whether a curated (YT Music) playlist with this id has already been
  /// saved locally — drives the "Kaydet" bookmark state on [PlaylistScreen].
  bool isPlaylistSaved(String sourcePlaylistId) =>
      _playlists.any((p) => p.sourcePlaylistId == sourcePlaylistId);

  /// Saves a snapshot of a curated playlist's current tracks as a local
  /// playlist, or removes it if it was already saved — a bookmark toggle,
  /// same shape as [toggleFavorite]. Re-saving after the curated playlist's
  /// contents changed upstream does NOT refresh it; it's a snapshot, not a
  /// live mirror, consistent with how [CustomPlaylist] works everywhere else.
  Future<void> toggleSavedPlaylist({
    required String sourcePlaylistId,
    required String name,
    required List<Track> tracks,
  }) async {
    final existingIndex = _playlists.indexWhere(
      (p) => p.sourcePlaylistId == sourcePlaylistId,
    );
    if (existingIndex != -1) {
      _playlists.removeAt(existingIndex);
    } else {
      _playlists.add(
        CustomPlaylist(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          createdAt: DateTime.now(),
          tracks: tracks,
          sourcePlaylistId: sourcePlaylistId,
        ),
      );
    }
    await _storage.savePlaylists(_playlists);
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist(String playlistId, Track track) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    final existing = _playlists[index];
    _playlists[index] = existing.copyWith(
      tracks: existing.tracks.where((t) => t != track).toList(),
    );
    await _storage.savePlaylists(_playlists);
    notifyListeners();
  }
}
