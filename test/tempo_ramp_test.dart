import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metronome/metronome.dart';
import 'package:metronome/metronome_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TempoRampConfig', () {
    test('builds stages and clamps the final increment to the target', () {
      const config = TempoRampConfig(
        startBpm: 80,
        targetBpm: 92,
        stepBpm: 5,
        measuresPerStep: 2,
      );

      final stages = config.stages(beatsPerMeasure: 4);

      expect(stages.map((stage) => stage.bpm), [80, 85, 90, 92]);
      expect(config.totalStages, 4);
      expect(stages.first.duration, const Duration(seconds: 6));
      expect(stages.last.isTarget, isTrue);
      expect(stages.last.measures, isNull);
      expect(stages.last.startsAt, greaterThan(const Duration(seconds: 16)));
    });

    test('calculates exact time to target from stage tempos', () {
      const config = TempoRampConfig(
        startBpm: 60,
        targetBpm: 80,
        stepBpm: 10,
        measuresPerStep: 1,
      );

      final stages = config.stages(beatsPerMeasure: 4);

      expect(stages[1].startsAt, const Duration(seconds: 4));
      expect(
        stages.last.startsAt,
        const Duration(microseconds: 7428571),
      );
    });

    test('rejects invalid upward ramp values', () {
      expect(
        () => const TempoRampConfig(
          startBpm: 120,
          targetBpm: 120,
          stepBpm: 5,
          measuresPerStep: 4,
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => const TempoRampConfig(
          startBpm: 80,
          targetBpm: 120,
          stepBpm: 0,
          measuresPerStep: 4,
        ).validate(),
        throwsArgumentError,
      );
    });
  });

  test('decodes native progress payloads', () {
    final progress = TempoRampProgress.fromMap(<Object?, Object?>{
      'status': 'running',
      'currentBpm': 95,
      'stageIndex': 3,
      'completedMeasures': 2,
      'totalStages': 9,
    });

    expect(progress.status, TempoRampStatus.running);
    expect(progress.currentBpm, 95);
    expect(progress.stageIndex, 3);
    expect(progress.completedMeasures, 2);
    expect(progress.totalStages, 9);
  });

  test('sends ramp configuration over the method channel', () async {
    final calls = <MethodCall>[];
    final platform = MethodChannelMetronome();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null),
    );

    await platform.configureTempoRamp(
      const TempoRampConfig(
        startBpm: 80,
        targetBpm: 120,
        stepBpm: 5,
        measuresPerStep: 4,
      ),
    );

    expect(calls.single.method, 'configureTempoRamp');
    expect(calls.single.arguments, <String, int>{
      'startBpm': 80,
      'targetBpm': 120,
      'stepBpm': 5,
      'measuresPerStep': 4,
    });
  });
}
