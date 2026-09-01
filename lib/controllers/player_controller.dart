import 'dart:async';
import 'dart:ui' show Color;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:palette_generator/palette_generator.dart';

import '../models/track.dart';
import '../models/transition_plan.dart';
import '../services/catalog_service.dart';
import '../services/automix_log.dart';
import '../services/soloud_audio_service.dart';
import '../services/stream_service.dart';
import 'managers/automix_manager.dart';
import 'managers/queue_manager.dart';

/// Central facade the UI talks to for playback. Owns no HTTP/audio details
/// itself — delegates stream resolution to [StreamService], actual playback
/// (including automix dual-deck crossfades) to [SoloudAudioService], and
/// queue/radio-continuation bookkeeping to [QueueManager]; this class wires
/// them together and decides what to do with a resolved automix plan — see
/// [_reactToAutomixPlan]. The *timing* of the blend belongs to
/// [SoloudAudioService.armCrossfade], which can read the deck's real play
/// position; this class only decides when a plan is ready to be handed over.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.catalogService,
    required this.streamService,
    required this.audioService,
    required this.queueManager,
    required this.automixManager,
  }) {
    _positionSub = audioService.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
      automixManager.onPositionUpdate(
        position: pos,
        duration: duration,
        currentVideoId: currentTrack?.videoId,
        nextVideoId: queueManager.upcoming.isEmpty
            ? null
            : queueManager.upcoming.first.videoId,
      );
      _reactToAutomixPlan();
    });
    _completedSub = audioService.completedStream.listen(
      (_) => _onTrackCompleted(),
    );
    _errorSub = audioService.errorStream.listen((message) {
      _errorMessage = message;
      _isLoading = false;
      notifyListeners();
    });
    _bufferingSub = audioService.bufferingStream.listen((buffering) {
      if (_isBuffering != buffering) {
        _isBuffering = buffering;
        notifyListeners();
      }
    });
    _durationSub = audioService.durationStream.listen((discoveredDuration) {
      if ((currentTrack?.duration == null || currentTrack?.duration == Duration.zero) &&
          _runtimeDuration == null &&
          discoveredDuration > Duration.zero) {
        _runtimeDuration = discoveredDuration;
        notifyListeners();
        automixManager.onPositionUpdate(
          position: _position,
          duration: discoveredDuration,
          currentVideoId: currentTrack?.videoId,
          nextVideoId: queueManager.upcoming.isEmpty
              ? null
              : queueManager.upcoming.first.videoId,
        );
      }
    });
    queueManager.addListener(notifyListeners);
  }

  final CatalogService catalogService;
  final StreamService streamService;
  final SoloudAudioService audioService;
  final QueueManager queueManager;
  final AutomixManager automixManager;

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<void> _completedSub;
  late final StreamSubscription<String> _errorSub;
  late final StreamSubscription<bool> _bufferingSub;

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration? _runtimeDuration;
  String? _errorMessage;
  bool _isFetchingRadio = false;
  Color? _accentColor;

  // Automix crossfade orchestration — which resolved plan we've already reacted
  // to, and how far through reacting we got. The *timing* of the blend itself is
  // no longer tracked here: `SoloudAudioService.armCrossfade` owns it, because
  // only the engine can read its own play position precisely enough. See
  // [_reactToAutomixPlan].
  TransitionPlan? _reactedToPlan;
  bool _automixStandbyPrepareStarted = false;
  bool _automixCrossfadeArmed = false;

  QueueManager get queue => queueManager;
  AutomixManager get automix => automixManager;
  Track? get currentTrack => queueManager.current;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration? get duration => currentTrack?.duration ?? _runtimeDuration;
  String? get errorMessage => _errorMessage;

  /// A vibrant color pulled from the current track's cover art (via
  /// [PaletteGenerator]) — drives the Now Playing background wash and mini
  /// player accent. Null until extraction finishes, or if there's no cover.
  Color? get accentColor => _accentColor;

  /// True for the whole duration of an in-progress automix crossfade — lets
  /// the seek bar / mini player progress show a distinct "in transition"
  /// treatment instead of the plain playback progress.
  bool get isAutomixCrossfading => audioService.isCrossfading;

  /// Plays a track with no list context (e.g. tapped from search results) —
  /// the queue becomes just this track, radio-eligible so it gets extended
  /// with `/api/catalog/watch/{id}` results as it nears the end.
  Future<void> playFromSearch(Track track) async {
    queueManager.startWithSingleTrack(track);
    await _playCurrent();
  }

  /// Plays an explicit ordered list starting at [startIndex] (album/playlist
  /// context) — no radio auto-continuation once it ends.
  Future<void> playFromList(List<Track> tracks, {int startIndex = 0}) async {
    queueManager.startWithList(tracks, startIndex: startIndex);
    await _playCurrent();
  }

  Future<void> skipToNext() async {
    if (!queueManager.advance()) return;
    await _playCurrent();
  }

  Future<void> skipToPrevious() async {
    // Standard player convention: past a few seconds in, "previous" restarts
    // the current track instead of jumping back — only a fresh tap within
    // the first moments goes to the actual previous track.
    if (_position > const Duration(seconds: 3) || !queueManager.hasPrevious) {
      seek(Duration.zero);
      return;
    }
    if (!queueManager.retreat()) return;
    await _playCurrent();
  }

  void jumpToQueueIndex(int index) {
    if (index == queueManager.currentIndex) return;
    queueManager.jumpTo(index);
    unawaited(_playCurrent());
  }

  Future<void> _onTrackCompleted() async {
    if (_reactedToPlan != null && !_automixCrossfadeArmed) {
      AutomixLog.write(
        'track completed naturally before crossfade threshold was '
        'reached — falling back to a hard cut',
      );
    }
    if (queueManager.hasNext) {
      await skipToNext();
      return;
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> _playCurrent() async {
    final track = currentTrack;
    if (track == null) return;

    automixManager.onCurrentTrackChanged();
    _resetAutomixOrchestration();
    _isLoading = true;
    _isBuffering = false;
    _isPlaying = false;
    _position = Duration.zero;
    _runtimeDuration = null;
    _errorMessage = null;
    _accentColor = null;
    notifyListeners();
    unawaited(_extractAccentColor(track));

    try {
      final streamInfo = await streamService.resolve(track.videoId);
      await audioService.play(streamInfo.url);
      _isPlaying = true;
    } catch (e) {
      _errorMessage = 'Oynatılamadı: $e';
      _isPlaying = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    unawaited(_ensureRadioFilled());
  }

  void _resetAutomixOrchestration() {
    _reactedToPlan = null;
    _automixStandbyPrepareStarted = false;
    _automixCrossfadeArmed = false;
    audioService.disarmCrossfade();
  }

  /// Reacts to [AutomixManager]'s resolved plan for the current→next track
  /// pair. The manager only decides *whether* a plan exists (drives the
  /// badge); this decides what to do about it:
  ///
  /// 1. The instant a new plan appears, ease the live deck onto its
  ///    loudness-matched gain, so the blend doesn't open with a level step.
  ///    Nothing else is applied to track A — the backend no longer re-pitches
  ///    the track that is already playing (see `timeline.py`), which is what
  ///    used to put a tempo jump seconds into a song whose transition was still
  ///    minutes away.
  /// 2. Kick off preloading the next track on the standby deck.
  /// 3. Once that deck actually has audio, hand the plan to the audio service
  ///    and let it watch for track A's exit point itself.
  ///
  /// Deliberately no position arithmetic here any more. The previous version
  /// re-scaled the engine's reported position by the speed ratio to recover
  /// source time — but `SoLoud.getPosition` already returns source time with the
  /// ratio folded in, so the correction was applied twice and moved the trigger
  /// by seconds over the length of a track.
  void _reactToAutomixPlan() {
    final plan = automixManager.currentPlan;
    if (plan == null) {
      if (_reactedToPlan != null) _resetAutomixOrchestration();
      return;
    }

    if (!identical(_reactedToPlan, plan)) {
      _reactedToPlan = plan;
      _automixStandbyPrepareStarted = false;
      _automixCrossfadeArmed = false;
      audioService.applyLoudnessMatch(plan);
    }

    if (!_automixStandbyPrepareStarted) {
      _automixStandbyPrepareStarted = true;
      final next = queueManager.upcoming.isEmpty
          ? null
          : queueManager.upcoming.first;
      if (next != null) {
        unawaited(_prepareAutomixStandby(next));
      }
    }

    // Never arm before the standby deck has actually buffered past track B's
    // entry point — arming without it degrades to a silent hard cut (the queue
    // advances but the engine has nothing to swap to). Arming late is fine: the
    // service moves the exit point forward by whole bars so the blend still
    // lands on the grid.
    if (!_automixCrossfadeArmed &&
        audioService.isStandbyReadyFor(plan.timing.trackBStartSource)) {
      _automixCrossfadeArmed = true;
      audioService.armCrossfade(
        plan: plan,
        onComplete: _onAutomixCrossfadeComplete,
      );
    }
  }

  Future<void> _prepareAutomixStandby(Track next) async {
    try {
      final streamInfo = await streamService.resolve(next.videoId);
      await audioService.prepareStandbyDeck(streamInfo.url);
      AutomixLog.write('standby deck ready (${next.title})');
      // The position stream drives arming, but it only ticks every 200ms and the
      // plan may already be past its exit point by now — react immediately.
      _reactToAutomixPlan();
    } catch (e) {
      debugPrint('Automix standby preload failed: $e');
    }
  }

  /// The audio engine has already swapped decks by the time this fires —
  /// just move the queue pointer and refresh UI-facing state to match,
  /// without touching playback itself (unlike [skipToNext]).
  void _onAutomixCrossfadeComplete() {
    queueManager.advance();
    final newTrack = currentTrack;
    automixManager.onCurrentTrackChanged();
    _resetAutomixOrchestration();
    _runtimeDuration = null;
    _isPlaying = true;
    _errorMessage = null;
    _accentColor = null;
    if (newTrack != null) unawaited(_extractAccentColor(newTrack));
    unawaited(_ensureRadioFilled());
    notifyListeners();
  }

  Future<void> _extractAccentColor(Track track) async {
    final url = track.thumbnailUrl;
    if (url == null) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        maximumColorCount: 16,
      );
      if (currentTrack?.videoId != track.videoId) return; // stale, superseded
      final color =
          palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.darkVibrantColor?.color ??
          palette.mutedColor?.color;
      if (color == null) return;
      _accentColor = color;
      notifyListeners();
    } catch (e) {
      debugPrint('Accent color extraction failed: $e');
    }
  }

  Future<void> _ensureRadioFilled() async {
    if (_isFetchingRadio || !queueManager.needsRadioRefill) return;
    final anchor = currentTrack;
    if (anchor == null) return;

    _isFetchingRadio = true;
    try {
      final tracks = await catalogService.watchPlaylist(anchor.videoId);
      queueManager.appendRadioTracks(tracks);
    } catch (e) {
      debugPrint('Radio queue refill failed: $e');
    } finally {
      _isFetchingRadio = false;
    }
  }

  void togglePlayPause() {
    if (currentTrack == null) return;
    if (_isPlaying) {
      audioService.pause();
    } else {
      audioService.resume();
    }
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void seek(Duration position) {
    audioService.seek(position);
    _position = position;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub.cancel();
    _durationSub.cancel();
    _completedSub.cancel();
    _errorSub.cancel();
    _bufferingSub.cancel();
    queueManager.removeListener(notifyListeners);
    super.dispose();
  }
}
