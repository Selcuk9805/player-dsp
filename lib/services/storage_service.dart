import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_playlist.dart';
import '../models/track.dart';

/// Thin wrapper around [SharedPreferences] — the single place that knows the
/// on-disk key names for user settings (DSP server address, automix toggle)
/// and local library data (favorites, custom playlists). Favorites/playlists
/// are purely local — `another-dsp` never sees them.
class StorageService {
  StorageService(this._prefs);

  static const _kDspServerUrl = 'dsp_server_url';
  static const _kAutomixEnabled = 'automix_enabled';
  static const _kFavorites = 'favorites_v1';
  static const _kPlaylists = 'playlists_v1';

  static const defaultDspServerUrl = 'http://127.0.0.1:8000';
  static const _kTimeStretch = 'time_stretch_enabled';

  final SharedPreferences _prefs;

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  String get dspServerUrl =>
      _prefs.getString(_kDspServerUrl) ?? defaultDspServerUrl;

  Future<void> setDspServerUrl(String url) =>
      _prefs.setString(_kDspServerUrl, url);

  bool get automixEnabled => _prefs.getBool(_kAutomixEnabled) ?? false;

  Future<void> setAutomixEnabled(bool enabled) =>
      _prefs.setBool(_kAutomixEnabled, enabled);

  /// Whether the incoming track may be stretched further than a plain resampler allows, with
  /// the pitch change cancelled by the pitch shifter. Widens how many pairs can be beat-matched
  /// at the cost of running a phase vocoder over the incoming deck.
  bool get timeStretchEnabled => _prefs.getBool(_kTimeStretch) ?? true;

  Future<void> setTimeStretchEnabled(bool enabled) =>
      _prefs.setBool(_kTimeStretch, enabled);

  List<Track> getFavorites() {
    final raw = _prefs.getString(_kFavorites);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>().map(Track.fromJson).toList();
  }

  Future<void> saveFavorites(List<Track> tracks) => _prefs.setString(
    _kFavorites,
    jsonEncode(tracks.map((t) => t.toJson()).toList()),
  );

  List<CustomPlaylist> getPlaylists() {
    final raw = _prefs.getString(_kPlaylists);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .cast<Map<String, dynamic>>()
        .map(CustomPlaylist.fromJson)
        .toList();
  }

  Future<void> savePlaylists(List<CustomPlaylist> playlists) =>
      _prefs.setString(
        _kPlaylists,
        jsonEncode(playlists.map((p) => p.toJson()).toList()),
      );
}
