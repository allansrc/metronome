import 'dart:async';

import 'metronome_platform_interface.dart';

class Metronome {
  static final Metronome _instance = Metronome._internal();
  factory Metronome() {
    return _instance;
  }
  Metronome._internal();
  final MetronomePlatform _platform = MetronomePlatform.instance;
  bool get isInitialized => _initialized;
  bool _initialized = false;

  /// ```
  /// metronome.tickStream.listen(
  ///   (int tick) {
  ///     print("tick: $tick");
  ///   },
  /// );
  /// ```
  Stream<int> get tickStream => _platform.tickController.stream;

  ///initialize the metronome
  /// ```
  /// @param mainPath: the path of the main audio file
  /// @param accentedPath: the path of the accented audio file, default ''
  /// @param bpm: the beats per minute, default `120`
  /// @param volume: the volume of the metronome, default `50`%
  /// @param accentPattern: group sizes per bar (first beat of each group is accented), default `[4]`
  /// @param sampleRate: the sampleRate of the metronome, default `44100`
  /// @param manageAudioSession: whether the plugin configures and activates AVAudioSession on iOS, default `true`.
  /// Set it to `false` when the host application manages the shared audio session. Ignored on other platforms.
  /// ```
  Future<void> init(
    String mainPath, {
    String accentedPath = '',
    int bpm = 120,
    int volume = 50,
    bool enableTickCallback = false,
    List<int> accentPattern = const [4],
    int sampleRate = 44100,
    bool manageAudioSession = true,
  }) async {
    try {
      MetronomePlatform.instance.init(
        mainPath,
        accentedPath: accentedPath,
        bpm: bpm,
        volume: volume,
        enableTickCallback: enableTickCallback,
        accentPattern: accentPattern,
        sampleRate: sampleRate,
        manageAudioSession: manageAudioSession,
      );
      _initialized = true;
      return;
    } catch (err) {
      _initialized = false;
      rethrow;
    }
  }

  ///play the metronome
  Future<void> play() async {
    return MetronomePlatform.instance.play();
  }

  ///pause the metronome
  Future<void> pause() async {
    return MetronomePlatform.instance.pause();
  }

  ///stop the metronome
  Future<void> stop() async {
    return MetronomePlatform.instance.stop();
  }

  ///get the volume of the metronome
  Future<int> getVolume() async {
    int? volume = await MetronomePlatform.instance.getVolume();
    return volume ?? 50;
  }

  ///set the volume of the metronome (0-100)
  Future<void> setVolume(int volume) async {
    return MetronomePlatform.instance.setVolume(volume);
  }

  ///check if the metronome is playing
  Future<bool?> isPlaying() async {
    return MetronomePlatform.instance.isPlaying();
  }

  ///set the audio file of the metronome
  Future<void> setAudioFile(
      {String mainPath = '', String accentedPath = ''}) async {
    return MetronomePlatform.instance
        .setAudioFile(mainPath: mainPath, accentedPath: accentedPath);
  }

  ///set the bpm of the metronome
  Future<void> setBPM(int bpm) async {
    return MetronomePlatform.instance.setBPM(bpm);
  }

  ///get the bpm of the metronome
  Future<int> getBPM() async {
    int? bpm = await MetronomePlatform.instance.getBPM();
    return bpm ?? 120;
  }

  ///set the accent pattern (group sizes; first beat of each group is accented)
  Future<void> setAccentPattern(List<int> accentPattern) async {
    return MetronomePlatform.instance.setAccentPattern(accentPattern);
  }

  ///get the accent pattern of the metronome
  Future<List<int>> getAccentPattern() async {
    List<int>? pattern = await MetronomePlatform.instance.getAccentPattern();
    return pattern ?? const [4];
  }

  ///destroy the metronome
  Future<void> destroy() async {
    _initialized = false;
    return MetronomePlatform.instance.destroy();
  }
}
