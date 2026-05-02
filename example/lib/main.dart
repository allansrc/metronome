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
    print("init:${_metronomePlugin.isInitialized}");
    _metronomePlugin.tickStream.listen(
      (int tick) {
        currentTick = tick;
        print("tick: $tick");
        if (metronomeIcon == metronomeIconRight) {
          metronomeIcon = metronomeIconLeft;
        } else {
          metronomeIcon = metronomeIconRight;
        }
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
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
                onChangeEnd: (val) {
                  _metronomePlugin.setBPM(bpm);
                },
                onChanged: (val) {
                  bpm = val.toInt();
                  currentTick = 0;
                  setState(() {});
                },
              ),
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
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            currentTick = 0;
            if (isplaying) {
              _metronomePlugin.pause();
              isplaying = false;
            } else {
              _metronomePlugin.play();
              isplaying = true;
            }
            setState(() {});
          },
          child: Icon(isplaying ? Icons.pause : Icons.play_arrow),
        ),
      ),
    );
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
