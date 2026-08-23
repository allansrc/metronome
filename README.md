# Metronome

[![pub package](https://img.shields.io/pub/v/metronome.svg)](https://pub.dev/packages/metronome)

An efficient, accurate, cross-platform Flutter metronome plugin.
Supports configurable BPM, volume, accent patterns (musical groupings), custom audio sources, and real-time tick callbacks.

**Version 2.0** refactored most of the code for better performance (BPM>600), less resource usage, and more accurate callbacks. **Version 3.0** replaces a single beat count with `accentPattern` (group sizes) so compound and odd meters match real accent groupings; see [time-signature.md](time-signature.md) for theory and examples.

![Metronome](https://raw.githubusercontent.com/biner88/metronome/main/screenshot/demo2.png)

## Demo

[Live preview](https://biner88.github.io/metronome/)

## Supported Platforms

| Platform | Audio Engine        | Min Version     |
|----------|---------------------|-----------------|
| Android  | `AudioTrack`        | SDK 19          |
| iOS      | `AVAudioEngine`     | iOS 12.0        |
| macOS    | `AVAudioEngine`     | macOS 10.14     |
| Web      | Web Audio API       | Modern browsers |
| Windows  | Native C API        | —               |

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  metronome: ^3.0.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:metronome/metronome.dart';

final metronome = Metronome();

await metronome.init(
  'assets/audio/snare.wav',
  accentedPath: 'assets/audio/claves44_wav.wav',
  bpm: 120,
  volume: 50,
  enableTickCallback: true,
  accentPattern: const [4],
  sampleRate: 44100,
  // iOS only. Keep true unless the host app manages AVAudioSession.
  manageAudioSession: true,
);

await metronome.play();
```

## API Reference

### Initialization

#### `init(String mainPath, { ... })`

Initializes the metronome engine. Must be called before any other method.

| Parameter            | Type     | Default | Description                                              |
|----------------------|----------|---------|----------------------------------------------------------|
| `mainPath`           | `String` | —       | **Required.** Path to the main click audio file (asset or absolute path). |
| `accentedPath`       | `String` | `''`    | Path to the accented (beat-1) audio file. Falls back to `mainPath` if empty. |
| `bpm`                | `int`    | `120`   | Beats per minute. Must be > 0.                           |
| `volume`             | `int`    | `50`    | Volume level, 0–100.                                     |
| `enableTickCallback` | `bool`   | `false` | Whether to emit events on `tickStream`.                  |
| `accentPattern`      | `List<int>` | `[4]` | Group sizes in one bar. The first beat of each group uses the accented sound. Sum = beats per bar. Example: `[3, 3]` is 6/8 compound (A b b A b b); `[2, 2, 3]` is a common 7/8 grouping. |
| `sampleRate`         | `int`    | `44100` | Audio sample rate in Hz.                                 |

### iOS audio session management

`manageAudioSession` controls whether the plugin configures and activates the shared `AVAudioSession` during initialization.

The default value is `true`, which preserves the existing behavior. The plugin uses the `playAndRecord` category, `videoRecording` mode, and activates the audio session.

Set it to `false` when the host application already manages `AVAudioSession`, for example through the Flutter [`audio_session`](https://pub.dev/packages/audio_session) package. The host application must configure and activate its audio session before starting audio playback:

```dart
await metronome.init(
  'assets/audio/snare.wav',
  manageAudioSession: false,
);
```

This parameter only affects iOS. It does not change audio session behavior on Android, macOS, Windows, or Web.

### Play

```dart
metronome.play();
metronome.pause();
metronome.stop();
metronome.destroy();
```

| Method       | Returns         | Description                              |
|--------------|-----------------|------------------------------------------|
| `play()`     | `Future<void>`  | Starts the metronome. Loops continuously.|
| `pause()`    | `Future<void>`  | Pauses playback.                         |
| `stop()`     | `Future<void>`  | Stops playback and resets position.      |
| `destroy()`  | `Future<void>`  | Releases all native resources.           |

### State

```dart
bool ready = metronome.isInitialized;
bool? playing = await metronome.isPlaying();
```

| Property / Method | Type            | Description                                        |
|--------------------|-----------------|----------------------------------------------------|
| `isInitialized`    | `bool`          | `true` after successful `init()`, `false` after `destroy()`. |
| `isPlaying()`      | `Future<bool?>` | Returns `true` if currently playing.               |

### Runtime Configuration

All setters can be called while playing — the metronome adapts immediately.

```dart
metronome.setBPM(140);
metronome.setVolume(80);
metronome.setAccentPattern(const [3]);
metronome.setAudioFile(
  mainPath: 'assets/audio/snare.wav',
  accentedPath: 'assets/audio/claves.wav',
);
```

| Method                                         | Returns        | Description                                              |
|------------------------------------------------|----------------|----------------------------------------------------------|
| `setBPM(int bpm)`                              | `Future<void>` | Updates tempo. Restarts playback loop if playing.        |
| `getBPM()`                                     | `Future<int>`  | Returns current BPM (defaults to 120).                   |
| `setVolume(int volume)`                        | `Future<void>` | Sets volume (0–100).                                     |
| `getVolume()`                                  | `Future<int>`  | Returns current volume (defaults to 50).                 |
| `setAccentPattern(List<int> pattern)`          | `Future<void>` | Sets accent groups. Restarts playback loop if playing.   |
| `getAccentPattern()`                           | `Future<List<int>>` | Returns current accent pattern (defaults to `[4]`). |
| `setAudioFile({mainPath, accentedPath})`       | `Future<void>` | Hot-swaps audio files without re-initializing.           |


### Progressive tempo ramp

Arm an upward tempo ramp before playback, then use the normal play, pause, and
stop controls. Tempo changes happen at measure boundaries without restarting
the audio engine.

```dart
await metronome.configureTempoRamp(
  const TempoRampConfig(
    startBpm: 80,
    targetBpm: 120,
    stepBpm: 5,
    measuresPerStep: 4,
  ),
);

metronome.tempoRampStream.listen((progress) {
  print('${progress.currentBpm} BPM: ${progress.status.name}');
});

await metronome.play();
```

`pause()` preserves ramp progress, while `stop()` resets the armed ramp to its
starting BPM. Calling `setBPM()` disables ramp mode and keeps the manually
selected tempo. Ramp settings can be changed while paused or stopped.

### TimeSignature

### Tick Stream

`enableTickCallback` must be `true` in `init()` for events to be emitted.

```dart
metronome.tickStream.listen((int tick) {
  // tick is the 0-based beat index within the current bar
  // e.g. for 4/4 time: 0, 1, 2, 3, 0, 1, 2, 3, ...
  print("tick: $tick");
});
```

## Audio File Requirements

- Files should be **WAV** format (PCM).
- Paths can be:
  - **Asset paths** — e.g. `'assets/sounds/click.wav'` (loaded via `rootBundle`).
  - **Absolute filesystem paths** — e.g. `'/data/user/0/.../click.wav'` (loaded via `dart:io`).
- On the **web** platform, only asset paths are practical.

## Architecture

```
┌─────────────────────────┐
│  Metronome  (singleton) │  ← Public Dart API
└────────────┬────────────┘
             │
   ┌─────────▼──────────┐
   │  MetronomePlatform  │  ← Abstract platform interface
   └─────────┬──────────┘
             │
     ┌───────┼────────┬──────────────┐
     ▼       ▼        ▼              ▼
  Method   Web     Windows       (future
  Channel  Audio   C API        platforms)
     │      API
     ▼
  ┌──────────────────────────────────┐
  │  Native engines per platform     │
  │                                  │
  │  iOS/macOS → AVAudioEngine       │
  │  Android   → AudioTrack          │
  │  Web       → AudioContext        │
  └──────────────────────────────────┘
```

Communication between Dart and native code uses:
- **`MethodChannel("metronome")`** — commands (init, play, stop, setBPM, etc.)
- **`EventChannel("metronome_tick")`** — streaming beat-index events back to Dart

### How Playback Works

1. **Init** — Dart loads audio files as raw bytes (`Uint8List`) and sends them to native via the method channel.
2. **Buffer generation** — The native engine builds a PCM buffer for one full bar:
   - The first beat of each group in `accentPattern` uses the *accented* sound.
   - Other beats use the *main* sound.
   - Each beat occupies `sampleRate * 60 / bpm` frames.
3. **Looping** — The bar buffer is scheduled to loop continuously.
4. **Tick events** — A platform-specific timer fires at each beat boundary and pushes the beat index back through the `EventChannel`.

### Platform-Specific Notes

#### iOS
- Audio session is configured as `.playAndRecord` with `mixWithOthers`, so the metronome coexists with other audio apps.
- Handles audio interruptions and route changes (e.g. Bluetooth headset connect/disconnect) by restarting the engine.

#### macOS
- Shares the same Swift source as iOS via `sharedDarwinSource`.
- No audio session management (not applicable on macOS).

#### Android
- Uses `AudioTrack` in `MODE_STREAM` with PCM 16-bit mono.
- A dedicated background thread writes the looping buffer to the track.
- Tick callbacks use `AudioTrack.setPositionNotificationPeriod()` for sample-accurate timing.
- Min SDK 19; backward-compatible volume API for older devices.

#### Web
- Uses the Web Audio API with a lookahead scheduler pattern for precise timing.
- `AudioBufferSourceNode` instances are created per beat and connected through a `GainNode`.
- Audio files are decoded and resampled to match the configured `sampleRate`.

## Project Structure

```
metronome/
├── lib/                        # Dart / Flutter layer
│   ├── metronome.dart          # Public API (singleton)
│   ├── metronome_platform_interface.dart
│   ├── metronome_method_channel.dart
│   └── metronome_web.dart      # Web platform implementation
├── darwin/                     # Shared iOS + macOS (Swift)
│   └── metronome/Sources/metronome/
│       ├── MetronomePlugin.swift
│       ├── Metronome.swift     # AVAudioEngine core
│       └── handler/EventTapHandler.swift
├── android/                    # Android (Java)
│   └── src/main/java/com/sumsg/metronome/
│       ├── MetronomePlugin.java
│       └── Metronome.java      # AudioTrack core
├── windows/                    # Windows (C++)
├── example/                    # Demo Flutter app
└── pubspec.yaml
```

## TODO

- [x] Add support for time signature [#2](https://github.com/biner88/metronome/issues/2)
- [x] Add Windows support
- [x] Add tickCallback for web

```dart
metronome.tickStream.listen((int tick) {
  print("tick: $tick");
});
```



## License

See [LICENSE](LICENSE) for details.