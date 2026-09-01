import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';

import '../models/transition_plan.dart';
import 'automix_log.dart';

const _sampleRate = 44100;
const _channels = Channels.stereo;
const _bytesPerFrame = 2 * 2; // s16le, stereo
const _bytesPerSecond = _sampleRate * _bytesPerFrame;

const _biquadFreqMin = 10.0;
const _biquadFreqMax = 16000.0;
const _biquadResonanceMin = 0.1;
const _biquadResonanceMax = 20.0;

/// How often the armed crossfade checks whether track A has reached its exit
/// point. The UI position stream ticks at 200ms, which was also what used to
/// gate the crossfade — at 124 BPM a beat is 484ms, so that alone put the
/// transition up to a *half beat* late, every time, with track B entering exactly
/// on its own beat. That is the flam ("at nali") in its purest form. Polling this
/// fast, plus [_ActiveDeckClock]'s sub-buffer interpolation and the overshoot
/// compensation in [_fireCrossfade], brings the residual error to ~1ms.
const _crossfadeArmTick = Duration(milliseconds: 5);

/// Automation tick during the blend. Driven by a [Stopwatch], never by counting
/// timer callbacks: Dart timers drift, and a previous version that accumulated a
/// fixed `elapsed += 0.02` per 20ms callback silently stretched the whole
/// envelope whenever the isolate was busy (which it is — see [_pumpDeck]).
const _crossfadeAutomationTick = Duration(milliseconds: 10);

/// SoLoud reports playback position once per audio buffer (2048 frames, ~46ms at
/// 44.1kHz), so between updates the position is stale. Interpolating past that by
/// more than a buffer or two means something has stalled — a pause, a buffer
/// underrun — so the estimate is capped rather than allowed to run away.
const _maxPositionExtrapolationSeconds = 0.12;

/// How long track B takes to drift back to its own natural tempo once the blend
/// is over. Snapping straight back to 1.0 (what [_finishCrossfade] used to do)
/// is an instant pitch jump of up to 6% right after the transition; spread over
/// this long the same change is inaudible.
const _speedRestoreDuration = Duration(seconds: 12);
const _speedRestoreTick = Duration(milliseconds: 50);

/// How long the active deck takes to settle on the gain a plan asks of it. Applied when the
/// plan arrives rather than at the first automation tick, where it landed as an audible step
/// change at the exact moment the blend began. In practice track A's gain is now always
/// unity, so this usually has nothing to do.
const _loudnessRampDuration = Duration(milliseconds: 1500);
const _loudnessRampTick = Duration(milliseconds: 50);

/// Ceiling for the global peak limiter, in dBFS.
///
/// Headroom for the overlap used to come from attenuating both decks toward an absolute
/// loudness target, which made the whole player audibly quieter the moment automix was
/// switched on — for a 1.4 dB median problem it was costing 3.5 dB of level. Catching the
/// few peaks the sum actually produces is the right place to solve that, and it leaves
/// ordinary playback at exactly the level it had before.
///
/// SoLoud's limiter treats `threshold` as maximiser DRIVE, not as a knee: -3 would push the
/// signal 3 dB INTO the ceiling. Zero means no drive, so it does nothing at all until the
/// mix exceeds the ceiling.
const _limiterCeilingDb = -1.0;
const _limiterDriveDb = 0.0;
const _limiterLookaheadMs = 4.0;
const _limiterReleaseMs = 80.0;

/// Track B may be asked for up to +6 dB to match track A, so the volume ceiling has to sit
/// above unity. The limiter, not this clamp, is what keeps the output safe.
const _maxDeckVolume = 4.0;

/// Below this much speed change, the pitch shifter is left out of the chain entirely.
///
/// Beat-matching works by playing the incoming track faster or slower, and SoLoud does that by
/// resampling — so its pitch moves with it. Cancelling that with the pitch shifter is what allows
/// the backend to stretch by up to 15% instead of 6%, which on real listening material is the
/// difference between 37% and 59% of transitions falling back to a token 2-bar fade.
///
/// It is not free: the shifter is a phase vocoder, and phase vocoders soften transients — which
/// here means kicks, the exact thing every other part of this system works to line up. So the
/// threshold is set where a plain resampler stops coping rather than anywhere lower. 6% is a
/// semitone, which DJs have run on pitch faders forever without anyone minding; correcting
/// something that small would spend real transient quality to fix an inaudible problem, and
/// would do it on the progressive-house pairs that already sound right.
///
/// The effect is that this feature is purely additive: every transition that worked before is
/// played exactly as it was, and only the ones that used to be unmatchable get the vocoder.
const _pitchCompensationThreshold = 0.06;

/// How far ahead of the play head each deck keeps decoded PCM buffered.
///
/// ffmpeg decodes far faster than realtime, so an unthrottled pump fed the entire
/// track into SoLoud within seconds of starting it. At 44.1kHz stereo s16le that
/// is ~176KB per second of audio — a 6-minute track is ~63MB, and with the
/// standby deck preloaded the pair sat at ~125MB of resident PCM on a phone.
const _bufferLookaheadSeconds = 45.0;

/// A standby deck has no play head to measure from yet, so it buffers a fixed
/// window instead — enough to cover any entry point the backend can choose
/// (~31s into track B) plus a full blend after it.
const _standbyBufferSeconds = 90.0;

/// Cap on a single pump read, so one tick can never block the isolate reading
/// tens of megabytes at once.
const _maxPumpChunkBytes = 2 * 1024 * 1024;

/// How much audio past track B's entry point must be buffered before a blend may be armed.
/// Covers the longest blend the backend produces plus a margin for the pump's own cadence.
const _standbyReadyMarginSeconds = 20.0;

/// Below this, track B's entry is close enough that seeking again would cost more than it
/// gains. Two kicks within a couple of milliseconds read as one event.
const _entryCorrectionFloorSeconds = 0.002;

/// Above this, the discrepancy is not the buffer-boundary effect the correction exists for —
/// it is a third of a beat at 124 BPM, so seeking by it could just as easily land on the
/// wrong beat. Leave it alone and let the log say what happened.
const _entryCorrectionCeilingSeconds = 0.15;

/// Interpolates the active deck's source position between SoLoud's once-per-buffer
/// updates.
///
/// [SoLoud.getPosition] returns a *source* time that already accounts for
/// relative play speed (`mStreamPosition += buffertime * mOverallRelativePlaySpeed`
/// in soloud.cpp), which is why callers must not scale it by the speed ratio
/// again — doing so used to push the crossfade trigger seconds away from its
/// planned point. What it does not do is update smoothly: it steps once per audio
/// buffer. Anchoring a stopwatch to each observed step recovers the time in
/// between.
class _ActiveDeckClock {
  Duration? _lastReported;
  double _anchorSeconds = 0;
  final Stopwatch _sinceAnchor = Stopwatch();

  void reset() {
    _lastReported = null;
    _anchorSeconds = 0;
    _sinceAnchor.stop();
    _sinceAnchor.reset();
  }

  void pause() => _sinceAnchor.stop();

  void resume() {
    // Drop the anchor instead of resuming the stopwatch: the position that was
    // current before the pause says nothing about how long the pause lasted.
    _lastReported = null;
    _sinceAnchor
      ..stop()
      ..reset();
  }

  /// [reported] is whatever `getPosition` says right now; [speedRatio] is the
  /// deck's current relative play speed, i.e. how much source time passes per
  /// second of wall clock.
  double sourceSeconds(Duration reported, double speedRatio) {
    if (reported != _lastReported) {
      _lastReported = reported;
      _anchorSeconds = reported.inMicroseconds / 1e6;
      _sinceAnchor
        ..reset()
        ..start();
      return _anchorSeconds;
    }
    final elapsed = math.min(
      _sinceAnchor.elapsedMicroseconds / 1e6,
      _maxPositionExtrapolationSeconds,
    );
    return _anchorSeconds + elapsed * speedRatio;
  }
}

/// One SoLoud `Bus` + whatever's currently loaded/playing through it. Two of
/// these exist for the app's whole lifetime — "deck" is a fixed role
/// (active/standby), not something created per track — so a crossfade is
/// just: prepare the standby deck, run both decks' automation for the
/// overlap window, then relabel which deck is "active".
class _Deck {
  Bus? bus;
  AudioSource? source;
  SoundHandle? handle;
  String? pcmFilePath;
  int? ffmpegSessionId;
  bool decodeFinished = false;
  bool endOfDataSignalled = false;
  int bytesFed = 0;

  /// Relative play speed currently applied to [handle]. Mirrored here because the
  /// position clock needs it to interpolate, and because it is ramped rather than
  /// set once.
  double speedRatio = 1.0;

  /// Whether this deck's bus currently has the pitch shifter in its chain.
  bool pitchShiftActive = false;

  /// Whether this blend decided to compensate at all. Fixed when the blend starts, so that the
  /// post-blend ramp back to normal speed cannot cross the threshold and drop the shifter
  /// mid-glide — which would be heard as the pitch jumping a semitone.
  bool pitchCompensating = false;

  /// LUFS-derived baseline gain (linear). Unlike the crossfade envelope, this is
  /// NOT reset back to 1.0 after the transition — it's a lasting perceptual
  /// loudness match.
  double baseGainLinear = 1.0;
  bool biquadActive = false;

  bool get isLoaded => source != null;
}

typedef _CurvePoint = ({double time, double value, String type, String curve});

/// Dual-deck playback engine built on flutter_soloud.
///
/// Single-track playback (search/skip/queue) never needs more than one deck
/// — [play] tears both down and starts fresh on deck 0. Automix crossfades
/// are the reason a second deck exists at all: [prepareStandbyDeck] preloads
/// the upcoming track without making it audible, and [armCrossfade] watches for
/// track A's planned exit point and then executes `another-dsp`'s `automation`
/// event lists verbatim (volume + biquad EQ, both decks) — it makes no strategy
/// decisions of its own.
///
/// Timing accuracy is this class's job, and the reason [armCrossfade] lives here
/// rather than in `PlayerController`: only the engine knows the deck's real play
/// position, and everything about how well two kicks land together follows from
/// how precisely that is read.
///
/// YouTube never serves raw PCM or a container SoLoud can decode natively
/// (webm/opus, m4a/aac), so ffmpeg still transcodes each deck's resolved CDN
/// URL to raw `s16le` PCM in a short-lived temp file; a periodic tail-pump
/// feeds newly-appended bytes into SoLoud's buffer stream. Nothing here
/// persists past the track/crossfade it was decoded for.
class SoloudAudioService {
  final _soloud = SoLoud.instance;
  final List<_Deck> _decks = [_Deck(), _Deck()];
  int _activeIndex = 0;

  _Deck get _active => _decks[_activeIndex];
  _Deck get _standby => _decks[1 - _activeIndex];

  Timer? _pumpTimer;
  Timer? _positionTimer;
  Timer? _armTimer;
  Timer? _crossfadeTimer;
  Timer? _speedRestoreTimer;
  Timer? _loudnessRampTimer;
  bool _activeDeckCompletedFired = false;
  bool _paused = false;
  bool _pumping = false;

  final _activeClock = _ActiveDeckClock();

  TransitionPlan? _armedPlan;
  double _armedTriggerSource = 0;
  double _armedEntryOffsetSeconds = 0;

  Stopwatch? _crossfadeClock;
  double _crossfadeTotalSec = 0;
  double _crossfadeExitSource = 0;
  double _crossfadeEntrySource = 0;
  double _crossfadeRatioB = 1.0;
  bool _entryCorrected = false;
  List<AutomationEvent> _activeVolumeEvents = const [];
  List<AutomationEvent> _standbyVolumeEvents = const [];
  List<BiquadFilterEvent> _activeBiquadEvents = const [];
  List<BiquadFilterEvent> _standbyBiquadEvents = const [];
  VoidCallback? _onCrossfadeComplete;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _completedController = StreamController<void>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  bool _isBuffering = false;

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<void> get completedStream => _completedController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<bool> get bufferingStream => _bufferingController.stream;

  bool get isBuffering => _isBuffering;
  bool get isCrossfading => _crossfadeClock != null;
  bool get isCrossfadeArmed => _armedPlan != null;
  bool get isStandbyLoaded => _standby.isLoaded;

  void _setBuffering(bool value) {
    if (_isBuffering == value) return;
    _isBuffering = value;
    _bufferingController.add(value);
  }

  /// Removes any stale auravibe_*.pcm files left in the temp directory from
  /// previous runs, crashes, or uncompleted skips to prevent disk bloating.
  static Future<void> _cleanOrphanedPcmFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return;
      final entities = tempDir.listSync();
      for (final entity in entities) {
        if (entity is File &&
            entity.path.contains('auravibe_') &&
            entity.path.endsWith('.pcm')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Orphaned PCM files cleanup error: $e');
    }
  }

  /// Whether the standby deck has actually buffered past [entrySeconds].
  ///
  /// [isStandbyLoaded] only says a buffer stream exists — [_prepareDeck] creates one
  /// synchronously, long before ffmpeg has decoded anything into it. Seeking a stream to a
  /// point it has not received yet gets you silence, so the blend has to wait for the bytes,
  /// not merely for the object.
  bool isStandbyReadyFor(double entrySeconds) {
    if (!_standby.isLoaded) return false;
    final needed =
        (entrySeconds + _standbyReadyMarginSeconds) * _bytesPerSecond;
    return _standby.bytesFed >= needed;
  }

  Future<void> init() async {
    // Opened here rather than in main(): the log exists to explain what this
    // engine did, so its lifetime should match the engine's.
    unawaited(AutomixLog.init());
    unawaited(_cleanOrphanedPcmFiles());
    if (_soloud.isInitialized) {
      return;
    }
    await _soloud.init(sampleRate: _sampleRate, channels: _channels);
    _enableLimiter();
    for (final deck in _decks) {
      deck.bus = _soloud.createMixingBus();
      deck.bus!.playOnEngine();
    }
  }

  /// Brickwall on the global output, so two decks summing during a blend can never clip.
  void _enableLimiter() {
    try {
      final limiter = _soloud.filters.limiterFilter;
      limiter.activate();
      limiter.threshold.value = _limiterDriveDb;
      limiter.outputCeiling.value = _limiterCeilingDb;
      limiter.attackTime.value = _limiterLookaheadMs;
      limiter.releaseTime.value = _limiterReleaseMs;
      limiter.wet.value = 1.0;
    } catch (e) {
      // Losing peak protection is not worth refusing to play over.
      debugPrint('Limiter unavailable (non-fatal): $e');
    }
  }

  /// Direct (non-crossfade) playback for a fresh track — tears down both
  /// decks (cancelling any in-flight automix preparation) and starts clean
  /// on deck 0. Used for search taps, manual skip/previous, and queue jumps.
  Future<void> play(String streamUrl) async {
    await _cancelCrossfade();
    await _teardownDeck(_decks[0]);
    await _teardownDeck(_decks[1]);
    _activeIndex = 0;
    _activeDeckCompletedFired = false;
    _paused = false;
    _activeClock.reset();

    await _prepareDeck(_active, streamUrl);
    _active.handle = _playOnDeck(_active, volume: 1.0);
    _active.speedRatio = 1.0;
    _ensurePumpTimer();
    _ensurePositionTimer();
  }

  /// Preloads the upcoming track on the standby deck without making it
  /// audible yet — ffmpeg decode + buffering starts immediately so enough
  /// PCM is ready by the time [armCrossfade] seeks into it.
  Future<void> prepareStandbyDeck(String streamUrl) async {
    if (_standby.isLoaded) return;
    await _prepareDeck(_standby, streamUrl);
    _ensurePumpTimer();
  }

  /// Eases the active deck onto the gain the plan asks of it.
  ///
  /// That gain is now normally unity — the backend matches the incoming track to the playing one
  /// rather than both to an absolute target — so this is usually a no-op, and exists to settle
  /// the deck back to unity if a previous blend's restore ramp is still in flight.
  void applyLoudnessMatch(TransitionPlan plan) {
    final gains = _deckGains(plan);
    _standby.baseGainLinear = gains.$2;

    // The previous blend's restore ramp is already walking this deck to unity — which is exactly
    // where track A's gain wants it — so leave it alone. Plans arrive roughly ten seconds into a
    // track and the restore runs for twelve, so these genuinely overlap; cancelling the restore
    // to start a second ramp would strand the deck at whatever speed the restore had reached.
    if (_speedRestoreTimer?.isActive ?? false) return;

    _active.baseGainLinear = gains.$1;

    final handle = _active.handle;
    if (handle == null) return;

    final from = _soloud.getVolume(handle);
    final to = _active.baseGainLinear;
    if ((to - from).abs() < 0.002) {
      _soloud.setVolume(handle, to);
      return;
    }

    _loudnessRampTimer?.cancel();
    final clock = Stopwatch()..start();
    final total = _loudnessRampDuration.inMilliseconds.toDouble();
    _loudnessRampTimer = Timer.periodic(_loudnessRampTick, (timer) {
      if (isCrossfading) {
        // The blend's own envelope owns the volume from here.
        timer.cancel();
        return;
      }
      final live = _active.handle;
      if (live == null) {
        timer.cancel();
        return;
      }
      final progress = (clock.elapsedMilliseconds / total).clamp(0.0, 1.0);
      _soloud.setVolume(live, _safeVolume(from + (to - from) * progress));
      if (progress >= 1.0) timer.cancel();
    });
  }

  /// The two decks' baseline gains, taken from the plan as-is.
  ///
  /// Deliberately NOT cross-normalised. An earlier version divided both by their peak so neither
  /// exceeded 1.0, which meant any boost asked of track B silently pulled track A down with it —
  /// the playing track got quieter to accommodate the one that had not started yet. The backend
  /// now expresses these relative to track A (whose gain is always 0 dB), so passing them
  /// through unchanged is what keeps automix-on and automix-off at the same level.
  (double, double) _deckGains(TransitionPlan plan) => (
    _dbToLinear(plan.trackAAutomation.lufsGainDb),
    _dbToLinear(plan.trackBAutomation.lufsGainDb),
  );

  /// Watches for track A reaching [TimingInfo.trackAStartCrossfadeSource] and
  /// runs the blend when it does.
  ///
  /// Call only once the standby deck is actually loaded — firing without audio to
  /// swap to degrades into a silent hard cut.
  void armCrossfade({
    required TransitionPlan plan,
    required VoidCallback onComplete,
  }) {
    if (!_standby.isLoaded || _standby.source == null) {
      AutomixLog.write(
        'armCrossfade: standby deck not ready, skipping transition',
      );
      onComplete();
      return;
    }

    _armTimer?.cancel();
    _armedPlan = plan;
    _onCrossfadeComplete = onComplete;
    _armedTriggerSource = plan.timing.trackAStartCrossfadeSource;
    _armedEntryOffsetSeconds = 0;

    AutomixLog.write(
      'armed: exit=${_armedTriggerSource.toStringAsFixed(3)}s '
      'entry=${plan.timing.trackBStartSource.toStringAsFixed(3)}s '
      'blend=${plan.timing.transitionDurationExecution.toStringAsFixed(2)}s '
      'ratioB=${plan.sync.trackBSpeedRatio} '
      'strategy=${plan.decision.strategy}',
    );

    _armTimer = Timer.periodic(_crossfadeArmTick, (_) => _checkArm());
  }

  double _barSeconds(TransitionPlan plan) {
    final bpm = plan.sync.targetBpm;
    return bpm > 0 ? 4 * 60.0 / bpm : 0.0;
  }

  void _checkArm() {
    final plan = _armedPlan;
    if (plan == null || _paused) return;

    final position = _estimatedActiveSourceSeconds;
    if (position < _armedTriggerSource) return;

    final overshoot = position - _armedTriggerSource;
    final barSeconds = _barSeconds(plan);

    // Being more than a bar past the exit means something moved the play head, not that the
    // poll was slow: a late arm (slow plan fetch), or a seek after arming. Firing now would
    // still land the beats together — the overshoot compensation is exact — but it would put
    // track B's entry mid-bar. Advancing the target by whole bars keeps both.
    if (barSeconds > 0 && overshoot > barSeconds) {
      final barsLate = (overshoot / barSeconds).ceil();
      _armedEntryOffsetSeconds += barsLate * barSeconds;
      _armedTriggerSource += barsLate * barSeconds;
      AutomixLog.write(
        '$barsLate bar(s) past the exit — moved to '
        '${_armedTriggerSource.toStringAsFixed(3)}s',
      );
      return;
    }

    _armTimer?.cancel();
    _armTimer = null;
    _fireCrossfade(plan, overshoot: overshoot);
  }

  double get _estimatedActiveSourceSeconds {
    final handle = _active.handle;
    if (handle == null) return 0;
    return _activeClock.sourceSeconds(
      _soloud.getPosition(handle),
      _active.speedRatio,
    );
  }

  /// Raw engine position of the active deck, in seconds. Already source time —
  /// SoLoud folds relative play speed into it internally, so callers must not
  /// scale by the speed ratio again.
  double get activeDeckSourceSeconds => _estimatedActiveSourceSeconds;

  void _fireCrossfade(TransitionPlan plan, {required double overshoot}) {
    final standbySource = _standby.source;
    if (standbySource == null) {
      AutomixLog.write('standby deck vanished before firing — hard cut');
      _armedPlan = null;
      final callback = _onCrossfadeComplete;
      _onCrossfadeComplete = null;
      callback?.call();
      return;
    }

    final ratioB = plan.sync.trackBSpeedRatio;

    // Track A is `overshoot` seconds past the planned exit. Track B has to start
    // that much further into itself for the two grids to line up — measured in
    // B's own timeline, which runs at ratioB source-seconds per second of
    // playback. Without this the blend inherits the whole polling error.
    final entrySeconds =
        plan.timing.trackBStartSource +
        (_armedEntryOffsetSeconds + overshoot) * ratioB;

    // Paused start, then seek, then unpause: playing first and seeking afterwards
    // leaks however many milliseconds of track B's opening the FFI round trip
    // takes, and makes the actual entry point depend on scheduler luck.
    final handle = _standby.bus!.play(
      standbySource,
      volume: 0.001,
      paused: true,
    );
    _standby.handle = handle;
    _standby.speedRatio = ratioB;
    _soloud.setRelativePlaySpeed(handle, ratioB);
    // Decided once, here: a stretch this deck will carry for the whole blend and the glide back.
    _standby.pitchCompensating =
        (ratioB - 1.0).abs() >= _pitchCompensationThreshold;
    _applyPitchCompensation(_standby, ratioB);
    _soloud.seek(handle, _toDuration(entrySeconds));

    _activeVolumeEvents = plan.trackAAutomation.volume;
    _standbyVolumeEvents = plan.trackBAutomation.volume;
    _activeBiquadEvents = plan.trackAAutomation.biquadFilters;
    _standbyBiquadEvents = plan.trackBAutomation.biquadFilters;

    _crossfadeTotalSec = _maxExecutionTime([
      ..._activeVolumeEvents.map((e) => e.executionTime),
      ..._standbyVolumeEvents.map((e) => e.executionTime),
      ..._activeBiquadEvents.map((e) => e.executionTime),
      ..._standbyBiquadEvents.map((e) => e.executionTime),
    ]);

    // Settle both decks on their t=0 automation *before* track B becomes
    // audible, so it never plays even one tick with its low end still open.
    _applyVolumeEvents(_active, _activeVolumeEvents, 0);
    _applyVolumeEvents(_standby, _standbyVolumeEvents, 0);
    _applyBiquadEvents(_active, _activeBiquadEvents, 0);
    _applyBiquadEvents(_standby, _standbyBiquadEvents, 0);

    _soloud.setPause(handle, false);

    _armedPlan = null;
    _crossfadeExitSource = _armedTriggerSource + overshoot;
    _crossfadeEntrySource = entrySeconds;
    _crossfadeRatioB = ratioB;
    _entryCorrected = false;
    _crossfadeClock = Stopwatch()..start();
    _crossfadeTimer?.cancel();
    _crossfadeTimer = Timer.periodic(
      _crossfadeAutomationTick,
      (_) => _tickCrossfade(),
    );

    AutomixLog.write(
      'fired: overshoot=${(overshoot * 1000).toStringAsFixed(1)}ms '
      'entry=${entrySeconds.toStringAsFixed(3)}s '
      'blend=${_crossfadeTotalSec.toStringAsFixed(2)}s',
    );
  }

  void _tickCrossfade() {
    final clock = _crossfadeClock;
    if (clock == null) return;
    final elapsed = clock.elapsedMicroseconds / 1e6;

    if (!_entryCorrected) {
      _entryCorrected = true;
      _correctStandbyEntry();
    }

    _applyVolumeEvents(_active, _activeVolumeEvents, elapsed);
    _applyVolumeEvents(_standby, _standbyVolumeEvents, elapsed);
    _applyBiquadEvents(_active, _activeBiquadEvents, elapsed);
    _applyBiquadEvents(_standby, _standbyBiquadEvents, elapsed);

    if (elapsed >= _crossfadeTotalSec) {
      unawaited(_finishCrossfade());
    }
  }

  /// Re-seats track B against where the engine actually started it.
  ///
  /// SoLoud only advances (and mixes) a voice on whole buffer boundaries — `mStreamPosition +=
  /// buffertime` in soloud.cpp, skipped entirely while a voice is paused — so an unpaused deck
  /// begins at the next mix block, not at the instant `setPause` was called. At 2048 frames that
  /// is up to 46ms of slip, which is squarely in flam territory, and it depends on engine
  /// internals this code should not be trying to predict.
  ///
  /// So it measures instead of predicting: both decks' positions come from the same
  /// block-updated counter, so comparing them says exactly how far apart the two grids really
  /// ended up. The correction runs on the blend's first tick, where track B's equal-power
  /// envelope still has it near-silent (~0.001 of full scale 10ms into a 15.6s fade), so
  /// re-seeking it is inaudible.
  void _correctStandbyEntry() {
    final activeHandle = _active.handle;
    final standbyHandle = _standby.handle;
    if (activeHandle == null || standbyHandle == null) return;

    final activeSource = _soloud.getPosition(activeHandle).inMicroseconds / 1e6;
    final standbySource = _soloud.getPosition(standbyHandle).inMicroseconds / 1e6;

    final elapsedInA = activeSource - _crossfadeExitSource;
    final expected = _crossfadeEntrySource + elapsedInA * _crossfadeRatioB;
    final error = expected - standbySource;

    if (error.abs() < _entryCorrectionFloorSeconds) {
      AutomixLog.write(
        'entry alignment ${(error * 1000).toStringAsFixed(2)}ms — no correction needed',
      );
      return;
    }
    if (error.abs() > _entryCorrectionCeilingSeconds) {
      AutomixLog.write(
        'entry alignment off by ${(error * 1000).toStringAsFixed(1)}ms — beyond the '
        'correction ceiling, leaving it alone',
      );
      return;
    }

    _soloud.seek(standbyHandle, _toDuration(standbySource + error));
    AutomixLog.write(
      'corrected track B entry by ${(error * 1000).toStringAsFixed(2)}ms',
    );
  }

  Future<void> _finishCrossfade() async {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _crossfadeClock = null;

    final oldActiveIndex = _activeIndex;
    _activeIndex = 1 - _activeIndex;
    _activeDeckCompletedFired = false;
    _activeClock.reset();

    final newHandle = _active.handle;
    if (newHandle != null) {
      _soloud.setVolume(newHandle, _safeVolume(_active.baseGainLinear));
      _releaseBiquad(_active);
      _startPostBlendRestore();
    }

    await _teardownDeck(_decks[oldActiveIndex]);

    _activeVolumeEvents = const [];
    _standbyVolumeEvents = const [];
    _activeBiquadEvents = const [];
    _standbyBiquadEvents = const [];

    final callback = _onCrossfadeComplete;
    _onCrossfadeComplete = null;
    callback?.call();
  }

  /// Eases the newly-active deck off both of the blend's adjustments — its beat-matched speed
  /// and its loudness-matched gain — back to neutral.
  ///
  /// Both corrections exist only to make the transition itself seamless, and neither should
  /// outlive it: a track left at its matched speed plays the rest of the song off-pitch, and one
  /// left at its matched gain makes each transition's level correction accumulate into the next.
  /// Spread over [_speedRestoreDuration] the changes are far too slow to hear (a 6% speed change
  /// or a 6 dB gain change over 12 seconds).
  void _startPostBlendRestore() {
    _speedRestoreTimer?.cancel();
    final deck = _active;
    final fromRatio = deck.speedRatio;
    final fromGain = deck.baseGainLinear;
    final speedSettled = (fromRatio - 1.0).abs() < 0.0005;
    final gainSettled = (fromGain - 1.0).abs() < 0.002;

    if (speedSettled && gainSettled) {
      deck.speedRatio = 1.0;
      deck.baseGainLinear = 1.0;
      return;
    }

    final clock = Stopwatch()..start();
    final total = _speedRestoreDuration.inMilliseconds.toDouble();
    _speedRestoreTimer = Timer.periodic(_speedRestoreTick, (timer) {
      final handle = deck.handle;
      if (handle == null || !identical(deck, _active) || isCrossfading) {
        timer.cancel();
        return;
      }
      final progress = (clock.elapsedMilliseconds / total).clamp(0.0, 1.0);

      final ratio = fromRatio + (1.0 - fromRatio) * progress;
      deck.speedRatio = ratio;
      _soloud.setRelativePlaySpeed(handle, ratio);
      // Tracked, not set once: the compensation has to follow the ratio down, or the track
      // would drift out of tune over the twelve seconds it takes to return to its own speed.
      _applyPitchCompensation(deck, ratio);

      final gain = fromGain + (1.0 - fromGain) * progress;
      deck.baseGainLinear = gain;
      _soloud.setVolume(handle, _safeVolume(gain));

      if (progress >= 1.0) timer.cancel();
    });
  }

  void _applyVolumeEvents(_Deck deck, List<AutomationEvent> events, double t) {
    final handle = deck.handle;
    if (events.isEmpty || handle == null) return;
    final envelope = _evalCurve(events.map(_automationPoint).toList(), t);
    _soloud.setVolume(handle, _safeVolume(envelope * deck.baseGainLinear));
  }

  void _applyBiquadEvents(
    _Deck deck,
    List<BiquadFilterEvent> events,
    double t,
  ) {
    final bus = deck.bus;
    if (events.isEmpty || bus == null) return;

    final filterValue = _biquadTypeValue(events.first.filterType);
    if (filterValue == null) {
      return; // unsupported type — skip silently, no crash
    }

    final freqEvents = events.where((e) => e.parameter == 'frequency').toList();
    final resEvents = events.where((e) => e.parameter == 'resonance').toList();
    if (freqEvents.isEmpty && resEvents.isEmpty) return;

    final biquad = bus.filters.biquadFilter;
    if (!deck.biquadActive) {
      biquad.activate();
      biquad.type().value = filterValue;
      deck.biquadActive = true;
    }
    if (freqEvents.isNotEmpty) {
      final freq = _evalCurve(freqEvents.map(_biquadPoint).toList(), t);
      biquad.frequency().value = freq.clamp(_biquadFreqMin, _biquadFreqMax);
    }
    if (resEvents.isNotEmpty) {
      final res = _evalCurve(resEvents.map(_biquadPoint).toList(), t);
      biquad.resonance().value = res.clamp(
        _biquadResonanceMin,
        _biquadResonanceMax,
      );
    }
  }

  /// Cancels the pitch change caused by playing [deck] at [ratio].
  ///
  /// Playing at ratio r raises the pitch by 12*log2(r) semitones, so shifting by the negative of
  /// that leaves the tempo change and removes the transposition — time-stretching, in effect.
  void _applyPitchCompensation(_Deck deck, double ratio) {
    final bus = deck.bus;
    if (bus == null || !deck.pitchCompensating) return;

    // Once the ramp has brought the speed back to normal there is nothing left to cancel.
    if ((ratio - 1.0).abs() < 0.0005) {
      _releasePitchShift(deck);
      deck.pitchCompensating = false;
      return;
    }

    try {
      final shifter = bus.filters.pitchShiftFilter;
      if (!deck.pitchShiftActive) {
        shifter.activate();
        deck.pitchShiftActive = true;
      }
      shifter.semitones().value = -12.0 * (math.log(ratio) / math.ln2);
    } catch (e) {
      // Playing slightly out of tune beats not playing at all.
      debugPrint('Pitch compensation unavailable (non-fatal): $e');
    }
  }

  void _releasePitchShift(_Deck deck) {
    if (!deck.pitchShiftActive || deck.bus == null) return;
    try {
      deck.bus!.filters.pitchShiftFilter.deactivate();
    } catch (e) {
      debugPrint('Pitch shift deactivate failed (non-fatal): $e');
    }
    deck.pitchShiftActive = false;
    deck.pitchCompensating = false;
  }

  /// Drops the bass-swap filter off a deck that has finished its blend. The sweep
  /// ends at 20Hz — below anything audible — so removing it is silent, but
  /// leaving a resonant biquad in the chain for the rest of the track isn't free.
  void _releaseBiquad(_Deck deck) {
    if (!deck.biquadActive || deck.bus == null) return;
    try {
      deck.bus!.filters.biquadFilter.deactivate();
    } catch (e) {
      debugPrint('Biquad deactivate failed (non-fatal): $e');
    }
    deck.biquadActive = false;
  }

  Future<void> _cancelCrossfade() async {
    _armTimer?.cancel();
    _armTimer = null;
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _speedRestoreTimer?.cancel();
    _speedRestoreTimer = null;
    _loudnessRampTimer?.cancel();
    _loudnessRampTimer = null;
    _crossfadeClock = null;
    _armedPlan = null;
    _armedEntryOffsetSeconds = 0;
    _onCrossfadeComplete = null;
  }

  /// Drops an armed (not yet fired) crossfade, e.g. because the queue changed.
  /// A blend already in progress is left alone — cutting it mid-fade would be
  /// more disruptive than letting it finish.
  void disarmCrossfade() {
    if (isCrossfading) return;
    _armTimer?.cancel();
    _armTimer = null;
    _armedPlan = null;
    _armedEntryOffsetSeconds = 0;
    _onCrossfadeComplete = null;
  }

  Future<void> _prepareDeck(_Deck deck, String streamUrl) async {
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/auravibe_${DateTime.now().microsecondsSinceEpoch}.pcm';
    deck.pcmFilePath = path;
    deck.bytesFed = 0;
    deck.decodeFinished = false;
    deck.endOfDataSignalled = false;
    deck.speedRatio = 1.0;

    final command =
        '-reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 '
        '-i "$streamUrl" -vn -f s16le -ar $_sampleRate -ac '
        '${_channels.count} -acodec pcm_s16le -y "$path"';

    final session = await FFmpegKit.executeAsync(command, (session) async {
      if (deck.ffmpegSessionId != session.getSessionId()) return;
      deck.decodeFinished = true;
      final file = File(path);
      if (file.existsSync() && identical(deck, _active)) {
        final totalSec = file.lengthSync() / _bytesPerSecond;
        if (totalSec > 0) {
          _durationController.add(
            Duration(milliseconds: (totalSec * 1000).round()),
          );
        }
      }
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode) &&
          !ReturnCode.isCancel(returnCode)) {
        _errorController.add('Ses akışı decode edilemedi (ffmpeg).');
      }
    });
    deck.ffmpegSessionId = session.getSessionId();

    deck.source = _soloud.setBufferStream(
      sampleRate: _sampleRate,
      channels: _channels,
      format: BufferType.s16le,
      bufferingType: BufferingType.preserved,
      bufferingTimeNeeds: 1,
      maxBufferSizeDuration: const Duration(hours: 2),
    );
  }

  SoundHandle _playOnDeck(_Deck deck, {required double volume}) {
    return deck.bus!.play(deck.source!, volume: volume);
  }

  void _ensurePumpTimer() {
    _pumpTimer?.cancel();
    _pumpTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      // A tick that overruns its 100ms period must not overlap the next one: both would read
      // from the same `bytesFed` offset and feed the same PCM twice, which puts duplicated
      // audio into the stream and desyncs reported position from what is actually playing.
      if (_pumping) return;
      _pumping = true;
      try {
        for (final deck in _decks) {
          if (deck.source != null) {
            await _pumpDeck(deck);
          }
        }
      } finally {
        _pumping = false;
      }
    });
  }

  /// How many bytes of this deck's PCM may be resident, given where it is playing.
  int _bufferBudgetBytes(_Deck deck) {
    final handle = deck.handle;
    if (handle == null || !_soloud.getIsValidVoiceHandle(handle)) {
      return (_standbyBufferSeconds * _bytesPerSecond).round();
    }
    final position = _soloud.getPosition(handle).inMilliseconds / 1000.0;
    return ((position + _bufferLookaheadSeconds) * _bytesPerSecond).round();
  }

  Future<void> _pumpDeck(_Deck deck) async {
    final path = deck.pcmFilePath;
    final source = deck.source;
    if (path == null || source == null) return;

    final file = File(path);
    if (!file.existsSync()) return;

    final length = file.lengthSync();
    final budget = _bufferBudgetBytes(deck);
    final wanted = math.min(length, budget);

    if (wanted > deck.bytesFed) {
      final chunkSize = math.min(wanted - deck.bytesFed, _maxPumpChunkBytes);
      final raf = await file.open();
      try {
        await raf.setPosition(deck.bytesFed);
        final chunk = await raf.read(chunkSize);
        if (chunk.isNotEmpty) {
          _soloud.addAudioDataStream(source, chunk);
          deck.bytesFed += chunk.length;
        }
      } finally {
        await raf.close();
      }
    }

    // Monitor buffering on the active deck
    if (identical(deck, _active)) {
      final handle = deck.handle;
      if (handle != null && _soloud.getIsValidVoiceHandle(handle)) {
        if (!deck.decodeFinished) {
          final position = _soloud.getPosition(handle).inMilliseconds / 1000.0;
          final buffered = deck.bytesFed / _bytesPerSecond;
          final remaining = buffered - position;
          if (remaining < 0.3 && !_isBuffering) {
            _setBuffering(true);
          } else if (remaining >= 1.0 && _isBuffering) {
            _setBuffering(false);
          }
        } else if (_isBuffering) {
          _setBuffering(false);
        }
      }
    }

    // Only once, and only when the whole decoded file really has been fed —
    // `budget` can legitimately hold data back for a while.
    if (deck.decodeFinished &&
        !deck.endOfDataSignalled &&
        file.lengthSync() <= deck.bytesFed) {
      deck.endOfDataSignalled = true;
      _soloud.setDataIsEnded(source);
    }
  }

  void _ensurePositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tickPosition(),
    );
  }

  void _tickPosition() {
    final handle = _active.handle;
    if (handle == null) return;
    if (!_soloud.getIsValidVoiceHandle(handle)) {
      if (_active.decodeFinished &&
          !_activeDeckCompletedFired &&
          !isCrossfading) {
        _activeDeckCompletedFired = true;
        _completedController.add(null);
      }
      return;
    }
    _positionController.add(_soloud.getPosition(handle));
  }

  void pause() {
    final handle = _active.handle;
    if (handle != null) _soloud.setPause(handle, true);
    _paused = true;
    _setBuffering(false);
    _activeClock.pause();
  }

  void resume() {
    final handle = _active.handle;
    if (handle != null) _soloud.setPause(handle, false);
    _paused = false;
    _activeClock.resume();
  }

  void seek(Duration position) {
    final handle = _active.handle;
    if (handle != null) _soloud.seek(handle, position);
    _activeClock.reset();
  }

  void setVolume(double volume) {
    final handle = _active.handle;
    if (handle != null) _soloud.setVolume(handle, volume.clamp(0.0, 1.0));
  }

  Future<void> stop() async {
    await _cancelCrossfade();
    await _teardownDeck(_decks[0]);
    await _teardownDeck(_decks[1]);
    _activeClock.reset();
  }

  Future<void> _teardownDeck(_Deck deck) async {
    final sessionId = deck.ffmpegSessionId;
    deck.ffmpegSessionId = null;
    if (sessionId != null && !deck.decodeFinished) {
      try {
        await FFmpegKit.cancel(sessionId);
      } catch (e) {
        debugPrint('FFmpeg session cancel failed: $e');
      }
    }

    final handle = deck.handle;
    deck.handle = null;
    if (handle != null && _soloud.isInitialized) {
      await _soloud.stop(handle);
    }

    _releaseBiquad(deck);
    _releasePitchShift(deck);

    final source = deck.source;
    deck.source = null;
    if (source != null && _soloud.isInitialized) {
      await _soloud.disposeSource(source);
    }

    final path = deck.pcmFilePath;
    deck.pcmFilePath = null;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('PCM temp file cleanup failed: $e');
      }
    }

    deck.decodeFinished = false;
    deck.endOfDataSignalled = false;
    deck.bytesFed = 0;
    deck.baseGainLinear = 1.0;
    deck.speedRatio = 1.0;
    if (identical(deck, _active)) {
      _setBuffering(false);
    }
  }

  Future<void> dispose() async {
    unawaited(AutomixLog.dispose());
    unawaited(_cleanOrphanedPcmFiles());
    _pumpTimer?.cancel();
    _positionTimer?.cancel();
    await _cancelCrossfade();
    await _teardownDeck(_decks[0]);
    await _teardownDeck(_decks[1]);
    for (final deck in _decks) {
      try {
        deck.bus?.dispose();
      } catch (e) {
        debugPrint('Bus dispose failed (non-fatal): $e');
      }
    }
    _setBuffering(false);
    await _bufferingController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
    await _errorController.close();
    if (_soloud.isInitialized) {
      await _soloud.deinitAsync();
    }
  }
}

double _dbToLinear(double db) => math.pow(10, db / 20).toDouble();

Duration _toDuration(double seconds) =>
    Duration(microseconds: (math.max(0.0, seconds) * 1e6).round());

/// SoLoud can auto-stop a voice whose volume reaches exactly 0.0, which during a
/// blend would kill the deck that is fading *in* before it ever becomes audible.
double _safeVolume(double volume) {
  final clamped = volume.clamp(0.0, _maxDeckVolume);
  return clamped <= 0.0 ? 0.001 : clamped;
}

double _maxExecutionTime(Iterable<double> times) {
  var max = 0.0;
  for (final t in times) {
    if (t > max) max = t;
  }
  return max;
}

_CurvePoint _automationPoint(AutomationEvent e) =>
    (time: e.executionTime, value: e.value, type: e.type, curve: e.curve);

_CurvePoint _biquadPoint(BiquadFilterEvent e) =>
    (time: e.executionTime, value: e.value, type: e.type, curve: e.curve);

double? _biquadTypeValue(String filterType) => switch (filterType) {
  'lowpass' => 0.0,
  'highpass' => 1.0,
  'bandpass' => 2.0,
  _ => null, // lowshelf/highshelf/peaking/notch/allpass — SoLoud's Biquad
  // Resonant filter doesn't support these; skip rather than crash.
};

/// Generic interpreter for both volume and biquad-parameter event lists:
/// `set` holds the previous value until it jumps instantly at its own time;
/// `fade*` interpolates from the previous point to this one using [curve].
/// `equal_power` uses `prev*cos(θ)+next*sin(θ)` — the same formula covers
/// both fade-out (1→0) and fade-in (0→1) correctly.
double _evalCurve(List<_CurvePoint> points, double t) {
  if (points.isEmpty) return 0;
  if (t <= points.first.time) return points.first.value;
  if (t >= points.last.time) return points.last.value;

  for (var i = 0; i < points.length - 1; i++) {
    final prev = points[i];
    final next = points[i + 1];
    if (t < next.time) {
      if (next.type == 'set' || next.curve == 'cut') return prev.value;
      final duration = next.time - prev.time;
      final progress = duration <= 0
          ? 1.0
          : ((t - prev.time) / duration).clamp(0.0, 1.0);
      if (next.curve == 'equal_power') {
        final theta = progress * (math.pi / 2);
        return prev.value * math.cos(theta) + next.value * math.sin(theta);
      }
      return prev.value + (next.value - prev.value) * progress;
    }
  }
  return points.last.value;
}
