import 'package:flutter/foundation.dart';

import '../../models/track.dart';

/// Owns the play queue and its position. Doesn't touch playback itself —
/// [PlayerController] reacts to queue changes and drives the audio engine.
///
/// Two ways a queue gets started:
/// - [startWithSingleTrack]: user played a track with no list context (e.g.
///   straight from search). [radioEligible] becomes true, so the controller
///   knows it's allowed to extend the queue with `/api/catalog/watch/{id}`
///   results (YT Music's own "radio" continuation) as playback nears the end.
/// - [startWithList]: user played from an explicit ordered list (album/
///   playlist). The queue is exactly that list — no radio auto-continuation.
class QueueManager extends ChangeNotifier {
  final List<Track> _queue = [];
  int _currentIndex = -1;
  bool _radioEligible = false;
  final Set<String> _seenIds = {};

  List<Track> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get radioEligible => _radioEligible;

  Track? get current => _currentIndex >= 0 && _currentIndex < _queue.length
      ? _queue[_currentIndex]
      : null;

  List<Track> get upcoming => _currentIndex + 1 < _queue.length
      ? _queue.sublist(_currentIndex + 1)
      : const [];

  bool get hasNext => _currentIndex + 1 < _queue.length;
  bool get hasPrevious => _currentIndex > 0;

  /// True once the radio buffer is running low and should be topped up.
  bool get needsRadioRefill => _radioEligible && upcoming.length < 3;

  void startWithSingleTrack(Track track) {
    _queue
      ..clear()
      ..add(track);
    _currentIndex = 0;
    _seenIds
      ..clear()
      ..add(track.videoId);
    _radioEligible = true;
    notifyListeners();
  }

  void startWithList(List<Track> tracks, {int startIndex = 0}) {
    if (tracks.isEmpty) return;
    _queue
      ..clear()
      ..addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    _seenIds
      ..clear()
      ..addAll(tracks.map((t) => t.videoId));
    _radioEligible = false;
    notifyListeners();
  }

  void appendRadioTracks(List<Track> tracks) {
    var added = false;
    for (final t in tracks) {
      if (_seenIds.add(t.videoId)) {
        _queue.add(t);
        added = true;
      }
    }
    if (added) notifyListeners();
  }

  bool advance() {
    if (!hasNext) return false;
    _currentIndex++;
    notifyListeners();
    return true;
  }

  bool retreat() {
    if (!hasPrevious) return false;
    _currentIndex--;
    notifyListeners();
    return true;
  }

  void jumpTo(int index) {
    if (index < 0 || index >= _queue.length || index == _currentIndex) return;
    _currentIndex = index;
    notifyListeners();
  }

  void clear() {
    _queue.clear();
    _currentIndex = -1;
    _seenIds.clear();
    _radioEligible = false;
    notifyListeners();
  }
}
