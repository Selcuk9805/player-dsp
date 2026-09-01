/// Mirrors `another-dsp`'s `TransitionPlan` schema (app/models/schemas.py,
/// schema_version 3). The client is a "dumb executor" — it interprets these
/// automation events verbatim and makes no strategy decisions of its own;
/// see the backend README's "API Entegrasyon Rehberi".
class AutomationEvent {
  const AutomationEvent({
    required this.executionTime,
    required this.value,
    required this.type,
    required this.curve,
  });

  final double executionTime;
  final double value;
  final String type; // "set" | "fadeVolume"
  final String curve; // "linear" | "equal_power" | "cut"

  factory AutomationEvent.fromJson(Map<String, dynamic> json) =>
      AutomationEvent(
        executionTime: (json['execution_time'] as num).toDouble(),
        value: (json['value'] as num).toDouble(),
        type: json['type'] as String,
        curve: json['curve'] as String? ?? 'linear',
      );
}

class BiquadFilterEvent {
  const BiquadFilterEvent({
    required this.filterType,
    required this.parameter,
    required this.executionTime,
    required this.value,
    required this.type,
    required this.curve,
  });

  final String filterType;
  final String parameter; // "frequency" | "resonance"
  final double executionTime;
  final double value;
  final String type; // "set" | "fadeFilterParameter"
  final String curve;

  factory BiquadFilterEvent.fromJson(Map<String, dynamic> json) =>
      BiquadFilterEvent(
        filterType: json['filter_type'] as String,
        parameter: json['parameter'] as String,
        executionTime: (json['execution_time'] as num).toDouble(),
        value: (json['value'] as num).toDouble(),
        type: json['type'] as String,
        curve: json['curve'] as String? ?? 'linear',
      );
}

class TrackAutomation {
  const TrackAutomation({
    required this.lufsGainDb,
    required this.camelotKey,
    required this.volume,
    required this.biquadFilters,
  });

  final double lufsGainDb;
  final String? camelotKey;
  final List<AutomationEvent> volume;
  final List<BiquadFilterEvent> biquadFilters;

  factory TrackAutomation.fromJson(Map<String, dynamic> json) =>
      TrackAutomation(
        lufsGainDb: (json['lufs_gain_db'] as num?)?.toDouble() ?? 0.0,
        camelotKey: json['camelot_key'] as String?,
        volume: (json['volume'] as List)
            .cast<Map<String, dynamic>>()
            .map(AutomationEvent.fromJson)
            .toList(),
        biquadFilters: ((json['biquad_filters'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(BiquadFilterEvent.fromJson)
            .toList(),
      );
}

class BeatAlignment {
  const BeatAlignment({
    required this.trackABeatSample,
    required this.trackBBeatSample,
    required this.sampleRate,
    required this.alignmentConfidence,
  });

  final int trackABeatSample;
  final int trackBBeatSample;

  /// Rate [trackABeatSample]/[trackBBeatSample] are counted in — the backend's
  /// *analysis* rate (22050 Hz), which has nothing to do with this app's output
  /// rate. Dividing those sample counts by the engine's own 44100 seeked track B
  /// to exactly half its intended entry point on every single transition, which
  /// is why [beatAlignmentSeconds] exists and why nothing should use the raw
  /// counts directly.
  final int sampleRate;

  final double alignmentConfidence;

  /// Track B's entry point in seconds. Prefer `timing.track_b_start_source`,
  /// which carries the same value without any rate conversion at all.
  double get trackBStartSeconds =>
      sampleRate > 0 ? trackBBeatSample / sampleRate : 0.0;

  factory BeatAlignment.fromJson(Map<String, dynamic> json) => BeatAlignment(
    trackABeatSample: json['track_a_beat_sample'] as int,
    trackBBeatSample: json['track_b_beat_sample'] as int,
    // Older cached responses predate the field; 22050 was always the value.
    sampleRate: (json['sample_rate'] as int?) ?? 22050,
    alignmentConfidence: (json['alignment_confidence'] as num).toDouble(),
  );
}

class SyncInfo {
  const SyncInfo({
    required this.targetBpm,
    required this.trackASpeedRatio,
    required this.trackBSpeedRatio,
    required this.beatAlignment,
  });

  final double targetBpm;
  final double trackASpeedRatio;
  final double trackBSpeedRatio;
  final BeatAlignment beatAlignment;

  factory SyncInfo.fromJson(Map<String, dynamic> json) => SyncInfo(
    targetBpm: (json['target_bpm'] as num).toDouble(),
    trackASpeedRatio: (json['track_a_speed_ratio'] as num).toDouble(),
    trackBSpeedRatio: (json['track_b_speed_ratio'] as num).toDouble(),
    beatAlignment: BeatAlignment.fromJson(
      json['beat_alignment'] as Map<String, dynamic>,
    ),
  );
}

class TimingInfo {
  const TimingInfo({
    required this.transitionDurationSource,
    required this.transitionDurationExecution,
    required this.trackAStartCrossfadeSource,
    required this.trackBStartSource,
    required this.trackBPlayDelayExecution,
  });

  final double transitionDurationSource;
  final double transitionDurationExecution;
  final double trackAStartCrossfadeSource;
  final double trackBStartSource;
  final double trackBPlayDelayExecution;

  factory TimingInfo.fromJson(Map<String, dynamic> json) => TimingInfo(
    transitionDurationSource: (json['transition_duration_source'] as num)
        .toDouble(),
    transitionDurationExecution: (json['transition_duration_execution'] as num)
        .toDouble(),
    trackAStartCrossfadeSource: (json['track_a_start_crossfade_source'] as num)
        .toDouble(),
    trackBStartSource: (json['track_b_start_source'] as num).toDouble(),
    trackBPlayDelayExecution: (json['track_b_play_delay_execution'] as num)
        .toDouble(),
  );
}

class TransitionDecision {
  const TransitionDecision({
    required this.strategy,
    required this.score,
    required this.confidence,
  });

  final String strategy;
  final double score;
  final double confidence;

  factory TransitionDecision.fromJson(Map<String, dynamic> json) =>
      TransitionDecision(
        strategy: json['strategy'] as String,
        score: (json['score'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class TransitionPlan {
  const TransitionPlan({
    required this.decision,
    required this.sync,
    required this.timing,
    required this.trackAAutomation,
    required this.trackBAutomation,
  });

  final TransitionDecision decision;
  final SyncInfo sync;
  final TimingInfo timing;
  final TrackAutomation trackAAutomation;
  final TrackAutomation trackBAutomation;

  factory TransitionPlan.fromJson(Map<String, dynamic> json) {
    final automation = json['automation'] as Map<String, dynamic>;
    return TransitionPlan(
      decision: TransitionDecision.fromJson(
        json['decision'] as Map<String, dynamic>,
      ),
      sync: SyncInfo.fromJson(json['sync'] as Map<String, dynamic>),
      timing: TimingInfo.fromJson(json['timing'] as Map<String, dynamic>),
      trackAAutomation: TrackAutomation.fromJson(
        automation['track_a'] as Map<String, dynamic>,
      ),
      trackBAutomation: TrackAutomation.fromJson(
        automation['track_b'] as Map<String, dynamic>,
      ),
    );
  }
}
