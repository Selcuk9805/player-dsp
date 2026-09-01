import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/transition_plan.dart';
import '../../services/automix_service.dart';
import '../../services/storage_service.dart';

enum AutomixBadgeState { hidden, red, yellow, green }

/// Drives the automix badge (hidden/red/yellow/green) and holds the DSP
/// crossfade plan for the upcoming track pair.
///
/// This phase covers the *observable* half of automix — real health polling
/// and real `/api/transition/plan` fetches driving genuine badge state.
/// Actually executing a plan (dual-deck crossfade, speed/gain automation) is
/// a separate follow-up; until then the resolved [currentPlan] is
/// informational only and playback still advances track-to-track normally.
class AutomixManager extends ChangeNotifier {
  AutomixManager(this._storage, this._automixService) {
    _enabled = _storage.automixEnabled;
    if (_enabled) _startHealthPolling();
  }

  final StorageService _storage;
  final AutomixService _automixService;

  bool _enabled = false;
  bool _serverReachable = false;
  bool _isFetchingPlan = false;
  TransitionPlan? _currentPlan;
  String? _planForPairKey;
  Timer? _healthTimer;

  bool get enabled => _enabled;
  bool get serverReachable => _serverReachable;
  TransitionPlan? get currentPlan => _currentPlan;

  AutomixBadgeState get badgeState {
    if (!_enabled) return AutomixBadgeState.hidden;
    if (!_serverReachable) return AutomixBadgeState.red;
    if (_currentPlan != null) return AutomixBadgeState.green;
    if (_isFetchingPlan) return AutomixBadgeState.yellow;
    // Enabled and healthy, but no transition is imminent yet — nothing
    // useful to show the user right now.
    return AutomixBadgeState.hidden;
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    await _storage.setAutomixEnabled(value);
    if (value) {
      _startHealthPolling();
    } else {
      _stopHealthPolling();
      _resetPlan();
    }
    notifyListeners();
  }

  Future<void> recheckHealthNow() => _checkHealthNow();

  void _startHealthPolling() {
    _healthTimer?.cancel();
    unawaited(_checkHealthNow());
    _healthTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkHealthNow(),
    );
  }

  void _stopHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _serverReachable = false;
  }

  Future<void> _checkHealthNow() async {
    final reachable = await _automixService.checkHealth();
    if (reachable != _serverReachable) {
      _serverReachable = reachable;
      notifyListeners();
    }
  }

  /// Call whenever a new track becomes current — any in-flight/resolved plan
  /// belonged to the previous pair and is now stale.
  void onCurrentTrackChanged() => _resetPlan();

  void _resetPlan() {
    if (_currentPlan == null && !_isFetchingPlan) return;
    _currentPlan = null;
    _isFetchingPlan = false;
    _planForPairKey = null;
    notifyListeners();
  }

  /// How soon after a track *starts* to request its plan. Analysis on a
  /// cache miss (yt-dlp download + librosa) can run long, so this fires
  /// early rather than waiting until the track is nearly over — the earlier
  /// request just has more runway to finish before the transition needs it.
  /// [_lateTriggerRemaining] stays as a safety net for the (normally
  /// unreachable) case where the early window passed without firing, e.g.
  /// the next track wasn't known yet.
  static const _earlyTriggerElapsed = Duration(seconds: 10);
  static const _lateTriggerRemaining = Duration(seconds: 30);

  /// Call on every playback position tick. Kicks off a plan fetch once
  /// [_earlyTriggerElapsed] has passed since the track started (or, failing
  /// that, once [_lateTriggerRemaining] is left — see above). No-op if
  /// disabled, unreachable, there's no next track yet, or a plan for this
  /// exact pair is already in flight/resolved.
  void onPositionUpdate({
    required Duration position,
    required Duration? duration,
    required String? currentVideoId,
    required String? nextVideoId,
  }) {
    if (!_enabled || !_serverReachable) return;
    if (currentVideoId == null || nextVideoId == null || duration == null) {
      return;
    }

    final remaining = duration - position;
    final withinEarlyWindow = position >= _earlyTriggerElapsed;
    final withinLateWindow = remaining <= _lateTriggerRemaining;
    if (!withinEarlyWindow && !withinLateWindow) return;

    final pairKey = '$currentVideoId>$nextVideoId';
    if (_planForPairKey == pairKey) return;

    _planForPairKey = pairKey;
    _isFetchingPlan = true;
    notifyListeners();

    _automixService
        .fetchPlan(trackAVideoId: currentVideoId, trackBVideoId: nextVideoId)
        .then((plan) {
          if (_planForPairKey != pairKey) return; // superseded meanwhile
          _currentPlan = plan;
          _isFetchingPlan = false;
          notifyListeners();
        })
        .catchError((Object e) {
          if (_planForPairKey != pairKey) return;
          debugPrint('Automix plan fetch failed: $e');
          _isFetchingPlan = false;
          _planForPairKey = null;
          notifyListeners();
        });
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    super.dispose();
  }
}
