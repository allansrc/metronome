import 'dart:async';
import 'dart:io';
import 'dart:js_interop';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;
import 'metronome_platform_interface.dart';

class MetronomeWeb extends MetronomePlatform {
  static void registerWith(Registrar registrar) {
    MetronomePlatform.instance = MetronomeWeb();
  }

  final StreamController<int> _tickController = StreamController<int>();
  static const int sampleSize = 16;
  static const int channels = 1;

  // Audio context and elements
  web.AudioContext? _audioContext;
  web.AudioBuffer? _mainSoundBuffer;
  web.AudioBuffer? _accentedSoundBuffer;
  web.AudioBuffer? _subdivisionSoundBuffer;
  web.AudioBuffer? _mainSoundBufferTemp;
  web.AudioBuffer? _accentedSoundBufferTemp;
  web.AudioBuffer? _subdivisionSoundBufferTemp;
  web.AudioBufferSourceNode? _currentSource;
  web.ScriptProcessorNode? _scriptNode;
  web.GainNode? gainNode;
  //
  bool _isPlaying = false;
  int _currentTick = 0;
  int _bpm = 120;
  List<int> _accentPattern = const [4];
  int _subdivision = 1;
  double _subdivisionVolume = 0.5;
  double _volume = 1.0;
  bool _enableTickCallback = false;
  int _sampleRate = 44100;
  //
  double _nextBeatTime = 0;
  int _scheduleTimer = 0;
  final double _lookahead = 0.1;
  final double _scheduleInterval = 0.05;

  int get _totalBeats =>
      _accentPattern.fold<int>(0, (sum, g) => sum + g);

  int get _totalSubTicks => _totalBeats * _subdivision;

  bool _isAccentBeat(int tick) {
    int pos = 0;
    for (final group in _accentPattern) {
      if (tick == pos) return true;
      pos += group;
    }
    return false;
  }

  void _validateAccentPattern(List<int> accentPattern) {
    if (accentPattern.isEmpty) {
      throw Exception('accentPattern must not be empty');
    }
    for (final g in accentPattern) {
      if (g < 1) {
        throw Exception('accentPattern groups must be >= 1');
      }
    }
  }

  @override
  Future<void> init(
    String mainPath, {
    String accentedPath = '',
    String subdivisionPath = '',
    int bpm = 120,
    int volume = 50,
    bool enableTickCallback = false,
    List<int> accentPattern = const [4],
    int subdivision = 1,
    int subdivisionVolume = 50,
    int sampleRate = 44100,
  }) async {
    _validateAccentPattern(accentPattern);
    _sampleRate = sampleRate;
    _audioContext = web.AudioContext(
      web.AudioContextOptions(
          latencyHint: 'interactive'.toJS, sampleRate: _sampleRate.toDouble()),
    );
    _mainSoundBuffer = await _bytesToAudioBuffer(mainPath);
    if (mainPath == '') {
      throw 'mainPath is empty';
    }
    if (accentedPath == '') {
      _accentedSoundBuffer = _mainSoundBuffer;
    } else {
      _accentedSoundBuffer = await _bytesToAudioBuffer(accentedPath);
    }
    if (subdivisionPath == '') {
      _subdivisionSoundBuffer = _mainSoundBuffer;
    } else {
      _subdivisionSoundBuffer = await _bytesToAudioBuffer(subdivisionPath);
    }
    _bpm = bpm;
    _accentPattern = List<int>.from(accentPattern);
    _subdivision = subdivision < 1 ? 1 : subdivision;
    _subdivisionVolume = subdivisionVolume / 100;
    _volume = volume / 100;
    _enableTickCallback = enableTickCallback;
  }

  @override
  Future<void> play() async {
    if (_isPlaying) return;
    _isPlaying = true;
    _currentTick = 0;
    startScheduler();
  }

  @override
  Future<void> pause() async {
    stopScheduler();
    _isPlaying = false;
    _currentSource?.stop();
    _currentSource = null;
    _scriptNode?.disconnect();
    _scriptNode = null;
  }

  @override
  Future<void> stop() async {
    await pause();
    _currentTick = 0;
  }

  @override
  Future<void> setVolume(int volume) async {
    if (_volume != volume) {
      _volume = volume / 100;
      if (gainNode != null) {
        gainNode?.gain.value = _volume;
      }
    }
  }

  @override
  Future<int?> getVolume() async {
    return (_volume * 100).round();
  }

  @override
  Future<List<int>?> getAccentPattern() async {
    return List<int>.from(_accentPattern);
  }

  @override
  Future<int?> getBPM() async {
    return _bpm;
  }

  @override
  Future<bool?> isPlaying() async {
    return _isPlaying;
  }

  @override
  Future<void> setBPM(int bpm) async {
    if (bpm != _bpm) {
      _bpm = bpm;
    }
  }

  @override
  Future<void> setAccentPattern(List<int> accentPattern) async {
    _validateAccentPattern(accentPattern);
    _accentPattern = List<int>.from(accentPattern);
  }

  @override
  Future<void> setSubdivision(int subdivision) async {
    if (subdivision >= 1) {
      _subdivision = subdivision;
    }
  }

  @override
  Future<int?> getSubdivision() async {
    return _subdivision;
  }

  @override
  Future<void> setSubdivisionVolume(int subdivisionVolume) async {
    _subdivisionVolume = subdivisionVolume / 100;
  }

  @override
  Future<int?> getSubdivisionVolume() async {
    return (_subdivisionVolume * 100).round();
  }

  @override
  Future<void> setAudioFile({
    String mainPath = '',
    String accentedPath = '',
  }) async {
    if (mainPath != '') {
      _mainSoundBufferTemp = await _bytesToAudioBuffer(mainPath);
    }
    if (accentedPath != '') {
      _accentedSoundBufferTemp = await _bytesToAudioBuffer(accentedPath);
    }
  }

  @override
  Future<void> destroy() async {
    await stop();
    _tickController.close();
    _mainSoundBuffer = null;
    _accentedSoundBuffer = null;
    _subdivisionSoundBuffer = null;
  }

  void startScheduler() {
    _nextBeatTime = _audioContext!.currentTime;
    _schedule();
  }

  void _schedule() {
    web.window.clearTimeout(_scheduleTimer);
    final subBeatDuration = 60.0 / (_bpm * _subdivision);
    while (_nextBeatTime < _audioContext!.currentTime + _lookahead) {
      _scheduleBeat(_nextBeatTime);
      _nextBeatTime += subBeatDuration;
    }
    _scheduleTimer = web.window.setTimeout(
      _schedule.toJS,
      (_scheduleInterval * 1000).round() as JSAny?,
    );
  }

  void _scheduleBeat(double time) {
    final isDownbeat = (_currentTick % _subdivision) == 0;
    final beatIndex = _currentTick ~/ _subdivision;
    final isAccented = isDownbeat && _isAccentBeat(beatIndex);

    web.AudioBuffer? buffer;
    double vol;
    if (isDownbeat) {
      buffer = isAccented ? _accentedSoundBuffer : _mainSoundBuffer;
      vol = _volume;
    } else {
      buffer = _subdivisionSoundBuffer ?? _mainSoundBuffer;
      vol = _volume * _subdivisionVolume;
    }

    final source = _audioContext!.createBufferSource();
    source.buffer = buffer;
    final gainNode = _audioContext!.createGain();
    gainNode.gain.value = vol;
    source.connect(gainNode);
    gainNode.connect(_audioContext!.destination);
    source.start(time);
    source.onEnded.listen((_) {
      if (_mainSoundBufferTemp != null) {
        _mainSoundBuffer = _mainSoundBufferTemp;
        _mainSoundBufferTemp = null;
      }
      if (_accentedSoundBufferTemp != null) {
        _accentedSoundBuffer = _accentedSoundBufferTemp;
        _accentedSoundBufferTemp = null;
      }
      if (_subdivisionSoundBufferTemp != null) {
        _subdivisionSoundBuffer = _subdivisionSoundBufferTemp;
        _subdivisionSoundBufferTemp = null;
      }
      if (_enableTickCallback) {
        tickController.add(_currentTick);
      }
      final ts = _totalSubTicks;
      _currentTick = ts < 1 ? 0 : (_currentTick + 1) % ts;
    });
  }

  void stopScheduler() {
    web.window.clearTimeout(_scheduleTimer);
    _nextBeatTime = 0;
  }

  Future<web.AudioBuffer> _bytesToAudioBuffer(String filePath) async {
    final byteData = await loadFileBytes(filePath);
    if (byteData.isEmpty) {
      throw Exception('File does not exist: $filePath');
    }
    final jsArrayBuffer = byteData.buffer;
    // print(await audioBuffer.toDart.then((value) => value.duration));
    final web.AudioBuffer audioBuffer =
        await _audioContext!.decodeAudioData(jsArrayBuffer as dynamic).toDart;
    return _convertAudioFormat(audioBuffer);
  }

  Future<web.AudioBuffer> _convertAudioFormat(web.AudioBuffer original) async {
    final framesPerBeat = (_sampleRate * 60 / _bpm).round();
    final newBuffer = _audioContext!
        .createBuffer(channels, framesPerBeat, _sampleRate.toDouble());
    final newChannel = newBuffer.getChannelData(0).toDart;
    const scaleFactor = 32767.0;
    const inverseScale = 1.0 / scaleFactor;

    for (var ch = 0; ch < original.numberOfChannels; ch++) {
      final channelData = original.getChannelData(ch).toDart;
      final maxCopyLength = framesPerBeat.clamp(0, channelData.length);

      for (var j = 0; j < maxCopyLength; j++) {
        final srcPos = (j * original.sampleRate / _sampleRate).round();

        if (srcPos < channelData.length) {
          double sample = channelData[srcPos];
          if (sampleSize == 16) {
            sample = (sample * scaleFactor).roundToDouble() * inverseScale;
          }

          if (original.numberOfChannels > 1) {
            newChannel[j] += sample / original.numberOfChannels;
          } else {
            newChannel[j] = sample;
          }
        }
      }
    }
    return newBuffer;
  }

  Future<Uint8List> loadFileBytes(String filePath) async {
    if (!filePath.startsWith('/')) {
      ByteData data = await rootBundle.load(filePath);
      return data.buffer.asUint8List();
    } else {
      File file = File(filePath);
      bool fileExists = await file.exists();
      if (!fileExists) {
        throw Exception('File does not exist: $filePath');
      }
      return await file.readAsBytes();
    }
  }
}
