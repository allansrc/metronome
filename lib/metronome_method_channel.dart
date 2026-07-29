import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'metronome_platform_interface.dart';

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

List<int>? _decodeAccentPattern(dynamic value) {
  if (value == null) return null;
  if (value is! List) return null;
  final out = <int>[];
  for (final e in value) {
    if (e is int) {
      out.add(e);
    } else if (e is num) {
      out.add(e.toInt());
    } else {
      return null;
    }
  }
  return out;
}

/// An implementation of [MetronomePlatform] that uses method channels.
class MethodChannelMetronome extends MetronomePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('metronome');
  final eventTickChannel = const EventChannel("metronome_tick");

  MethodChannelMetronome() {
    eventTickChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is int) {
          tickController.add(event);
        }
      },
      onError: (error) {
        // print("Tick Stream Error: $error");
      },
    );
  }
  @override
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
    if (mainPath == '') {
      throw Exception('Main path cannot be empty');
    }
    if (volume > 100 || volume < 0) {
      throw Exception('Volume must be between 0 and 100');
    }
    if (bpm <= 0) {
      throw Exception('BPM must be greater than 0');
    }
    _validateAccentPattern(accentPattern);
    if (sampleRate <= 0) {
      throw Exception('sampleRate must be greater than 0');
    }
    Uint8List mainFileBytes = await loadFileBytes(mainPath);
    Uint8List accentedFileBytes = Uint8List.fromList([]);
    if (accentedPath != '') {
      accentedFileBytes = await loadFileBytes(accentedPath);
    }
    try {
      await methodChannel.invokeMethod<void>('init', {
        'mainFileBytes': mainFileBytes,
        'accentedFileBytes': accentedFileBytes,
        'bpm': bpm,
        'volume': volume / 100.0,
        'enableTickCallback': enableTickCallback,
        'accentPattern': accentPattern,
        'sampleRate': sampleRate,
        'manageAudioSession': manageAudioSession,
      });
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<void> play() async {
    try {
      await methodChannel.invokeMethod<void>('play');
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<void> pause() async {
    try {
      await methodChannel.invokeMethod<void>('pause');
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<void> stop() async {
    try {
      await methodChannel.invokeMethod<void>('stop');
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<void> setBPM(int bpm) async {
    if (bpm <= 0) {
      throw Exception('BPM must be greater than 0');
    }
    try {
      await methodChannel.invokeMethod<void>('setBPM', {
        'bpm': bpm,
      });
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<int?> getBPM() async {
    try {
      return await methodChannel.invokeMethod<int>('getBPM');
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }

      return 0;
    }
  }

  @override
  Future<void> setAccentPattern(List<int> accentPattern) async {
    _validateAccentPattern(accentPattern);
    try {
      await methodChannel.invokeMethod<void>('setAccentPattern', {
        'accentPattern': accentPattern,
      });
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<List<int>?> getAccentPattern() async {
    try {
      final raw = await methodChannel.invokeMethod<dynamic>('getAccentPattern');
      return _decodeAccentPattern(raw);
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }

      return const [4];
    }
  }

  @override
  Future<int?> getVolume() async {
    try {
      return await methodChannel.invokeMethod<int>('getVolume');
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }

      return 0;
    }
  }

  @override
  Future<void> setVolume(int volume) async {
    if (volume > 100 || volume < 0) {
      throw Exception('Volume must be between 0 and 100');
    }
    try {
      await methodChannel.invokeMethod<void>('setVolume', {
        'volume': volume / 100,
      });
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<bool?> isPlaying() async {
    try {
      return await methodChannel.invokeMethod<bool>('isPlaying');
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }

      return false;
    }
  }

  @override
  Future<void> setAudioFile({
    String mainPath = '',
    String accentedPath = '',
  }) async {
    Uint8List mainFileBytes = Uint8List.fromList([]);
    Uint8List accentedFileBytes = Uint8List.fromList([]);
    if (mainPath != '') {
      mainFileBytes = await loadFileBytes(mainPath);
    }
    if (accentedPath != '') {
      accentedFileBytes = await loadFileBytes(accentedPath);
    }
    if (mainFileBytes.isEmpty && accentedFileBytes.isEmpty) {
      return;
    }
    try {
      await methodChannel.invokeMethod<void>('setAudioFile', {
        'mainFileBytes': mainFileBytes,
        'accentedFileBytes': accentedFileBytes,
      });
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Future<void> destroy() async {
    try {
      await methodChannel.invokeMethod<void>('destroy');
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
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
