import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transition_plan.dart';
import 'storage_service.dart';

const _youtubeWatchUrl = 'https://www.youtube.com/watch?v=';

/// Stretch limits asked of the backend, as a fraction of tempo.
///
/// The wider one is only safe because the player cancels the resulting pitch change (see
/// `SoloudAudioService._applyPitchCompensation`); asking for it without that would have the
/// incoming track arrive up to two and a half semitones out of tune. The narrow one is what a
/// plain resampler can carry.
const _stretchWithPitchCompensation = 0.15;
const _stretchWithoutPitchCompensation = 0.06;

/// Client for `another-dsp`'s automix endpoints — `/api/health` (drives the
/// badge's red/not-red state) and `/api/transition/plan` (the actual DSP
/// crossfade plan for a track pair). Same server as [CatalogService]/
/// [StreamService] — one DSP address, set once in Settings.
class AutomixService {
  AutomixService(this._storage, {http.Client? client})
    : _client = client ?? http.Client();

  final StorageService _storage;
  final http.Client _client;

  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('${_storage.dspServerUrl}/api/health');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches a crossfade plan for `trackA` (currently playing) → `trackB`
  /// (up next). Can take a while — the backend downloads+analyzes audio on a
  /// cache miss (yt-dlp + librosa), so this uses a generous timeout matching
  /// the backend README's own guidance (~90s worst case).
  Future<TransitionPlan> fetchPlan({
    required String trackAVideoId,
    required String trackBVideoId,
  }) async {
    final uri = Uri.parse('${_storage.dspServerUrl}/api/transition/plan');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'track_a': '$_youtubeWatchUrl$trackAVideoId',
            'track_b': '$_youtubeWatchUrl$trackBVideoId',
            'max_tempo_stretch': _storage.timeStretchEnabled
                ? _stretchWithPitchCompensation
                : _stretchWithoutPitchCompensation,
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      throw Exception(
        'Geçiş planı alınamadı (${response.statusCode}): ${response.body}',
      );
    }
    return TransitionPlan.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  void dispose() => _client.close();
}
