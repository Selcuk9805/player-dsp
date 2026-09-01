import 'dart:convert';

import 'package:http/http.dart' as http;

import 'storage_service.dart';

class StreamInfo {
  const StreamInfo({required this.url, this.expiresAt});

  final String url;
  final DateTime? expiresAt;
}

/// Client for `another-dsp`'s `/api/stream/resolve` — turns a YouTube video
/// id into a directly playable CDN URL. Resolution happens fresh per play
/// (not cached client-side): the URL embeds a short expiry and re-resolving
/// is cheap for the backend (yt-dlp metadata lookup, no download).
class StreamService {
  StreamService(this._storage, {http.Client? client})
    : _client = client ?? http.Client();

  final StorageService _storage;
  final http.Client _client;

  Future<StreamInfo> resolve(String videoId) async {
    final uri = Uri.parse('${_storage.dspServerUrl}/api/stream/resolve')
        .replace(queryParameters: {'video_id': videoId});

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Ses akışı çözümlenemedi (sunucuya ulaşılamıyor): $e');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Ses akışı çözümlenemedi (${response.statusCode}): ${response.body}',
      );
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final expiresAtEpoch = json['expiresAt'] as int?;
    return StreamInfo(
      url: json['url'] as String,
      expiresAt: expiresAtEpoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtEpoch * 1000),
    );
  }

  void dispose() => _client.close();
}
