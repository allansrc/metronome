import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'metronome_method_channel.dart';

abstract class MetronomePlatform extends PlatformInterface {
  /// Constructs a MetronomePlatform.
  MetronomePlatform() : super(token: _token);

  static final Object _token = Object();

  static MetronomePlatform _instance = MethodChannelMetronome();

  /// The default instance of [MetronomePlatform] to use.
  ///
  /// Defaults to [MethodChannelMetronome].
  static MetronomePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MetronomePlatform] when
  /// they register themselves.
  static set instance(MetronomePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  final StreamController<int> tickController =
      StreamController<int>.broadcast();

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
  }) {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<void> play() {
    throw UnimplementedError('play() has not been implemented.');
  }

  Future<void> pause() {
    throw UnimplementedError('pause() has not been implemented.');
  }

  Future<void> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  Future<int?> getVolume() {
    throw UnimplementedError('getVolume() has not been implemented.');
  }

  Future<void> setVolume(int volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  Future<bool?> isPlaying() {
    throw UnimplementedError('isPlaying() has not been implemented.');
  }

  Future<void> setAudioFile({
    String mainPath = '',
    String accentedPath = '',
  }) {
    throw UnimplementedError('setAudioFile() has not been implemented.');
  }

  Future<void> setBPM(int bpm) {
    throw UnimplementedError('setBPM() has not been implemented.');
  }

  Future<int?> getBPM() {
    throw UnimplementedError('getBPM() has not been implemented.');
  }

  Future<void> setAccentPattern(List<int> accentPattern) {
    throw UnimplementedError('setAccentPattern() has not been implemented.');
  }

  Future<List<int>?> getAccentPattern() {
    throw UnimplementedError('getAccentPattern() has not been implemented.');
  }

  Future<void> destroy() {
    throw UnimplementedError('destroy() has not been implemented.');
  }

  Future<void> setSubdivision(int subdivision) {
    throw UnimplementedError('setSubdivision() has not been implemented.');
  }

  Future<int?> getSubdivision() {
    throw UnimplementedError('getSubdivision() has not been implemented.');
  }

  Future<void> setSubdivisionVolume(int subdivisionVolume) {
    throw UnimplementedError('setSubdivisionVolume() has not been implemented.');
  }

  Future<int?> getSubdivisionVolume() {
    throw UnimplementedError('getSubdivisionVolume() has not been implemented.');
  }

  Stream<dynamic> onListenTick(onEvent) {
    throw UnimplementedError('onListenTick() has not been implemented.');
  }
}
