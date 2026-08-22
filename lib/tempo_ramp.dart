enum TempoRampStatus { idle, armed, running, paused, completed }

class TempoRampConfig {
  const TempoRampConfig({
    required this.startBpm,
    required this.targetBpm,
    required this.stepBpm,
    required this.measuresPerStep,
  });

  final int startBpm;
  final int targetBpm;
  final int stepBpm;
  final int measuresPerStep;

  int get totalStages {
    validate();
    return ((targetBpm - startBpm) / stepBpm).ceil() + 1;
  }

  void validate() {
    if (startBpm <= 0 || targetBpm <= 0 || stepBpm <= 0) {
      throw ArgumentError('Ramp BPM values must be greater than 0');
    }
    if (targetBpm <= startBpm) {
      throw ArgumentError('targetBpm must be greater than startBpm');
    }
    if (measuresPerStep <= 0) {
      throw ArgumentError('measuresPerStep must be greater than 0');
    }
  }

  Map<String, int> toMap() => <String, int>{
        'startBpm': startBpm,
        'targetBpm': targetBpm,
        'stepBpm': stepBpm,
        'measuresPerStep': measuresPerStep,
      };

  List<TempoRampStage> stages({required int beatsPerMeasure}) {
    validate();
    if (beatsPerMeasure <= 0) {
      throw ArgumentError.value(
        beatsPerMeasure,
        'beatsPerMeasure',
        'must be greater than 0',
      );
    }

    final result = <TempoRampStage>[];
    var bpm = startBpm;
    var elapsed = Duration.zero;
    var index = 0;
    while (true) {
      final isTarget = bpm == targetBpm;
      final duration = isTarget
          ? null
          : Duration(
              microseconds:
                  (measuresPerStep * beatsPerMeasure * 60000000 / bpm).round(),
            );
      result.add(
        TempoRampStage(
          index: index,
          bpm: bpm,
          measures: isTarget ? null : measuresPerStep,
          startsAt: elapsed,
          duration: duration,
        ),
      );
      if (isTarget) break;
      elapsed += duration!;
      bpm = (bpm + stepBpm).clamp(startBpm, targetBpm);
      index++;
    }
    return result;
  }
}

class TempoRampStage {
  const TempoRampStage({
    required this.index,
    required this.bpm,
    required this.measures,
    required this.startsAt,
    required this.duration,
  });

  final int index;
  final int bpm;
  final int? measures;
  final Duration startsAt;
  final Duration? duration;
  bool get isTarget => duration == null;
}

class TempoRampProgress {
  const TempoRampProgress({
    required this.status,
    required this.currentBpm,
    required this.stageIndex,
    required this.completedMeasures,
    required this.totalStages,
  });

  const TempoRampProgress.idle()
      : status = TempoRampStatus.idle,
        currentBpm = 0,
        stageIndex = 0,
        completedMeasures = 0,
        totalStages = 0;

  factory TempoRampProgress.fromMap(Map<Object?, Object?> map) {
    final statusName = map['status'] as String? ?? 'idle';
    return TempoRampProgress(
      status: TempoRampStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => TempoRampStatus.idle,
      ),
      currentBpm: (map['currentBpm'] as num?)?.toInt() ?? 0,
      stageIndex: (map['stageIndex'] as num?)?.toInt() ?? 0,
      completedMeasures: (map['completedMeasures'] as num?)?.toInt() ?? 0,
      totalStages: (map['totalStages'] as num?)?.toInt() ?? 0,
    );
  }

  final TempoRampStatus status;
  final int currentBpm;
  final int stageIndex;
  final int completedMeasures;
  final int totalStages;
}
