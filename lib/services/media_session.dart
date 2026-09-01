import 'package:audio_service/audio_service.dart';

import '../controllers/player_controller.dart';

/// Bridges [PlayerController] to the platform's media session — on Android,
/// the playback notification, the lock screen, and headset/bluetooth buttons.
///
/// This is what keeps playback alive in the background. Android freezes a
/// backgrounded process' timers and will kill it outright under memory
/// pressure; a foreground service of type `mediaPlayback` exempts it. That
/// matters more here than in most players: the automix crossfade is driven by
/// 5 ms and 10 ms Dart timers, so a frozen process would not merely pause the
/// audio, it would strand a transition halfway through with two decks
/// half-faded.
///
/// The handler deliberately owns no state. [PlayerController] remains the
/// single source of truth; this class mirrors it outward and forwards remote
/// commands back in. Both directions go through the controller's existing
/// public API, so the notification can never disagree with the UI.
class MediaSessionHandler extends BaseAudioHandler with SeekHandler {
  MediaSessionHandler(this._controller) {
    _controller.addListener(_publish);
    _publish();
  }

  final PlayerController _controller;

  // What was last pushed out, so an unchanged notification is not rebuilt on
  // every one of the controller's 200 ms position ticks. The duration is part
  // of the comparison because it can arrive late: tracks played from search
  // often carry no duration until the engine discovers it from the stream.
  String? _publishedId;
  Duration? _publishedDuration;

  // The controller exposes a single toggle, so the discrete remote commands
  // are guarded rather than issued blindly — a bluetooth "play" arriving while
  // already playing must not pause.
  @override
  Future<void> play() async {
    if (!_controller.isPlaying) _controller.togglePlayPause();
  }

  @override
  Future<void> pause() async {
    if (_controller.isPlaying) _controller.togglePlayPause();
  }

  @override
  Future<void> skipToNext() => _controller.skipToNext();

  @override
  Future<void> skipToPrevious() => _controller.skipToPrevious();

  @override
  Future<void> seek(Duration position) async => _controller.seek(position);

  @override
  Future<void> stop() async {
    if (_controller.isPlaying) _controller.togglePlayPause();
    await super.stop();
  }

  AudioProcessingState get _processingState {
    if (_controller.currentTrack == null) return AudioProcessingState.idle;
    if (_controller.isLoading) return AudioProcessingState.loading;
    if (_controller.isBuffering) return AudioProcessingState.buffering;
    return AudioProcessingState.ready;
  }

  void _publish() {
    final track = _controller.currentTrack;
    final duration = _controller.duration;

    if (track?.videoId != _publishedId || duration != _publishedDuration) {
      _publishedId = track?.videoId;
      _publishedDuration = duration;
      // During an automix crossfade both decks are audible, but the session can
      // only name one track. It stays on the outgoing one until the controller
      // itself considers the blend finished, which is also when the UI switches.
      mediaItem.add(
        track == null
            ? null
            : MediaItem(
                id: track.videoId,
                title: track.title,
                artist: track.artist,
                duration: duration,
                artUri: track.thumbnailUrl == null
                    ? null
                    : Uri.tryParse(track.thumbnailUrl!),
              ),
      );
    }

    final playing = _controller.isPlaying;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _processingState,
        playing: playing,
        updatePosition: _controller.position,
        queueIndex: _controller.queue.currentIndex,
      ),
    );
  }
}
