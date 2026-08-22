import 'dart:async';

import 'package:flutter/material.dart';
import 'package:metronome/metronome.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _metronomePlugin = Metronome();
  bool isplaying = false;
  int bpm = 120;
  int vol = 50;
  List<int> accentPattern = const [4];

  int get _totalBeats => accentPattern.fold(0, (a, b) => a + b);
  String metronomeIcon = 'assets/metronome-left.png';
  String metronomeIconRight = 'assets/metronome-right.png';
  String metronomeIconLeft = 'assets/metronome-left.png';
  final List wavs = [
    'base',
    'claves',
    'hihat',
    'snare',
    'sticks',
    'woodblock_high'
  ];
  String mainFileName = 'claves';
  String accentedFileName = 'woodblock_high';
  int currentTick = 0;
  bool rampEnabled = false;
  int rampStartBpm = 80;
  int rampTargetBpm = 120;
  int rampStepBpm = 5;
  int rampMeasuresPerStep = 4;
  TempoRampProgress rampProgress = const TempoRampProgress.idle();
  late final StreamSubscription<int> _tickSubscription;
  late final StreamSubscription<TempoRampProgress> _rampSubscription;

  TempoRampConfig get _rampConfig => TempoRampConfig(
        startBpm: rampStartBpm,
        targetBpm: rampTargetBpm,
        stepBpm: rampStepBpm,
        measuresPerStep: rampMeasuresPerStep,
      );

  @override
  void initState() {
    super.initState();
    _metronomePlugin.init(
      'assets/audio/${mainFileName}44_wav.wav',
      accentedPath: 'assets/audio/${accentedFileName}44_wav.wav',
      bpm: bpm,
      volume: vol,
      enableTickCallback: true,
      accentPattern: List<int>.from(accentPattern),
      sampleRate: 44100,
    );
    _tickSubscription = _metronomePlugin.tickStream.listen(
      (int tick) {
        currentTick = tick;
        if (metronomeIcon == metronomeIconRight) {
          metronomeIcon = metronomeIconLeft;
        } else {
          metronomeIcon = metronomeIconRight;
        }
        setState(() {});
      },
    );
    _rampSubscription = _metronomePlugin.tempoRampStream.listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          rampProgress = progress;
          if (progress.currentBpm > 0) bpm = progress.currentBpm;
        });
      },
    );
  }

  @override
  void dispose() {
    _tickSubscription.cancel();
    _rampSubscription.cancel();
    _metronomePlugin.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Metronome example'),
        ),
        body: Container(
          padding: const EdgeInsets.all(10),
          child: ListView(
            children: [
              Image.asset(
                metronomeIcon,
                height: 100,
                gaplessPlayback: true,
              ),
              if (_totalBeats > 1)
                SizedBox(
                  height: 60,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < _totalBeats; i++) _buildCircle(i),
                    ],
                  ),
                ),
              Text(
                'BPM:$bpm',
                style: const TextStyle(fontSize: 20),
              ),
              Slider(
                value: bpm.toDouble(),
                min: 30,
                max: 600,
                divisions: 570,
                onChangeEnd: rampEnabled
                    ? null
                    : (val) {
                        _metronomePlugin.setBPM(bpm);
                      },
                onChanged: rampEnabled
                    ? null
                    : (val) {
                        bpm = val.toInt();
                        currentTick = 0;
                        setState(() {});
                      },
              ),
              _buildRampSection(),
              Text(
                'Volume:$vol%',
                style: const TextStyle(fontSize: 20),
              ),
              Slider(
                value: vol.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                onChangeEnd: (val) {
                  _metronomePlugin.setVolume(vol);
                },
                onChanged: (val) {
                  vol = val.toInt();
                  setState(() {});
                },
              ),
              const Text(
                'Time Signature:',
                style: TextStyle(fontSize: 20),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildTimeSignButton('1/4', const [1]),
                  _buildTimeSignButton('2/4', const [2]),
                  _buildTimeSignButton('3/4', const [3]),
                  _buildTimeSignButton('4/4', const [4]),
                  _buildTimeSignButton('6/8', const [3, 3]),
                  _buildTimeSignButton('7/8', const [2, 2, 3]),
                  _buildTimeSignButton('12/8', const [3, 3, 3, 3]),
                ],
              ),
              const Text(
                'Main file:',
                style: TextStyle(fontSize: 20),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: wavs.map((wav) => _buildMainButton(wav)).toList(),
              ),
              const Text(
                'Accented file:',
                style: TextStyle(fontSize: 20),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: wavs.map((wav) => _buildAccentedButton(wav)).toList(),
              ),
            ],
          ),
        ),
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'stop',
              onPressed: _stopPlayback,
              child: const Icon(Icons.stop),
            ),
            const SizedBox(width: 12),
            FloatingActionButton(
              heroTag: 'play-pause',
              onPressed: _togglePlayback,
              child: Icon(isplaying ? Icons.pause : Icons.play_arrow),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    currentTick = 0;
    if (isplaying) {
      await _metronomePlugin.pause();
    } else {
      await _metronomePlugin.play();
    }
    if (!mounted) return;
    setState(() => isplaying = !isplaying);
  }

  Future<void> _stopPlayback() async {
    await _metronomePlugin.stop();
    if (!mounted) return;
    setState(() {
      isplaying = false;
      currentTick = 0;
    });
  }

  Future<void> _setRampEnabled(bool enabled) async {
    if (enabled) {
      await _metronomePlugin.configureTempoRamp(_rampConfig);
      bpm = rampStartBpm;
    } else {
      await _metronomePlugin.disableTempoRamp();
      bpm = await _metronomePlugin.getBPM();
    }
    if (!mounted) return;
    setState(() => rampEnabled = enabled);
  }

  Future<void> _configureRamp() async {
    if (!rampEnabled || isplaying) return;
    await _metronomePlugin.configureTempoRamp(_rampConfig);
    if (!mounted) return;
    setState(() => bpm = rampStartBpm);
  }

  Widget _buildRampSection() {
    final stages = _rampConfig.stages(beatsPerMeasure: timeSignature);
    final timeToTarget = stages.last.startsAt;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Progressive tempo ramp'),
              subtitle: Text(
                rampEnabled
                    ? '${rampProgress.status.name} · $bpm BPM'
                    : 'Increase BPM at measure boundaries',
              ),
              value: rampEnabled,
              onChanged: isplaying ? null : _setRampEnabled,
            ),
            _rampSlider(
              label: 'Start BPM',
              value: rampStartBpm,
              min: 30,
              max: 580,
              onChanged: (value) {
                setState(() {
                  rampStartBpm = value;
                  if (rampTargetBpm <= value) {
                    rampTargetBpm = (value + rampStepBpm).clamp(31, 600);
                  }
                });
              },
            ),
            _rampSlider(
              label: 'Target BPM',
              value: rampTargetBpm,
              min: rampStartBpm + 1,
              max: 600,
              onChanged: (value) => setState(() => rampTargetBpm = value),
            ),
            _rampSlider(
              label: 'Step',
              value: rampStepBpm,
              min: 1,
              max: 50,
              suffix: 'BPM',
              onChanged: (value) => setState(() => rampStepBpm = value),
            ),
            _rampSlider(
              label: 'Cadence',
              value: rampMeasuresPerStep,
              min: 1,
              max: 16,
              suffix: rampMeasuresPerStep == 1 ? 'measure' : 'measures',
              onChanged: (value) => setState(() => rampMeasuresPerStep = value),
            ),
            const SizedBox(height: 8),
            Text(
              '${stages.length} stages · ${_formatDuration(timeToTarget)} to target',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stages.length,
                separatorBuilder: (_, __) => const Icon(Icons.arrow_forward),
                itemBuilder: (context, index) {
                  final stage = stages[index];
                  final active = rampEnabled &&
                      index ==
                          rampProgress.stageIndex.clamp(0, stages.length - 1);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 112,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: active
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: active
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${stage.bpm} BPM',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(stage.isTarget
                            ? 'Hold'
                            : '${stage.measures} measures'),
                        if (stage.duration != null)
                          Text(_formatDuration(stage.duration!)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rampSlider({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    String suffix = 'BPM',
  }) {
    final enabled = !isplaying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value $suffix'),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: enabled ? (next) => onChanged(next.round()) : null,
          onChangeEnd: enabled ? (_) => _configureRamp() : null,
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return minutes == 0
        ? '${seconds}s'
        : '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildCircle(int index) {
    bool tick = currentTick == index;
    return Container(
      width: 35,
      height: 35,
      margin: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: tick ? 20 : 15,
            height: tick ? 20 : 15,
            decoration: BoxDecoration(
              color: tick ? Colors.red : Colors.white,
              borderRadius: BorderRadius.circular(tick ? 15 : 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentedButton(String name) {
    return ElevatedButton(
      child: Text(
        name,
        style: TextStyle(color: accentedFileName == name ? Colors.red : null),
      ),
      onPressed: () {
        accentedFileName = name;
        currentTick = 0;
        _metronomePlugin.setAudioFile(
            accentedPath: 'assets/audio/${name}44_wav.wav');
        setState(() {});
      },
    );
  }

  Widget _buildMainButton(String name) {
    return ElevatedButton(
      child: Text(
        name,
        style: TextStyle(color: mainFileName == name ? Colors.red : null),
      ),
      onPressed: () {
        mainFileName = name;
        currentTick = 0;
        _metronomePlugin.setAudioFile(
            mainPath: 'assets/audio/${name}44_wav.wav');
        setState(() {});
      },
    );
  }

  bool _samePattern(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _buildTimeSignButton(String text, List<int> pattern) {
    final selected = _samePattern(accentPattern, pattern);
    return ElevatedButton(
      onPressed: isplaying && rampEnabled
          ? null
          : () {
              currentTick = 0;
              timeSignature = ts;
              _metronomePlugin.setTimeSignature(ts);
              setState(() {});
            },
      child: Text(
        text,
        style: TextStyle(color: selected ? Colors.red : null),
      ),
      onPressed: () {
        currentTick = 0;
        accentPattern = List<int>.from(pattern);
        _metronomePlugin.setAccentPattern(List<int>.from(accentPattern));
        setState(() {});
      },
    );
  }
}
