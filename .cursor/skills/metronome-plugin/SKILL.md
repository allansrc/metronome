---
name: metronome-plugin
description: >-
  Develop and maintain the Metronome Flutter plugin across all platforms
  (Android, iOS, macOS, Web, Windows). Use when modifying native audio engines,
  the Dart API surface, platform channels, tick-callback logic, buffer
  generation, or audio session handling. Triggers: metronome, BPM, tick stream,
  AVAudioEngine, AudioTrack, Web Audio API, MethodChannel, EventChannel,
  time signature, audio buffer, click sound, accented beat.
---

# Metronome Flutter Plugin

Cross-platform Flutter plugin providing a precise, looping metronome with
configurable BPM, volume, time signature, custom audio sources, and real-time
tick callbacks.

## Key Concepts

- **Singleton API** — `Metronome()` in `lib/metronome.dart`. All public methods
  delegate to `MetronomePlatform.instance`.
- **Federated plugin** — follows Flutter's platform interface pattern:
  `MetronomePlatform` (abstract) → `MethodChannelMetronome` (mobile/desktop) /
  `MetronomeWeb` (browser).
- **Raw-byte audio transfer** — Dart loads WAV files as `Uint8List` and sends
  them to native over the method channel. Native engines never deal with file
  paths.
- **Bar-buffer looping** — each platform builds a PCM buffer for one full bar
  (accented beat 1 + normal beats 2..N) and loops it continuously.

## Codebase Map

```
lib/
  metronome.dart                  Public singleton API
  metronome_platform_interface.dart  Abstract contract
  metronome_method_channel.dart   MethodChannel + EventChannel impl
  metronome_web.dart              Web Audio API impl

darwin/metronome/Sources/metronome/
  MetronomePlugin.swift           Flutter plugin entry (iOS + macOS)
  Metronome.swift                 AVAudioEngine core, buffer generation
  handler/EventTapHandler.swift   FlutterStreamHandler for tick events

android/src/main/java/com/sumsg/metronome/
  MetronomePlugin.java            Flutter plugin entry
  Metronome.java                  AudioTrack core, buffer generation

windows/
  metronome_plugin_c_api.cpp      C API entry
  metronome_plugin.cpp            Plugin logic
  metronome.h                     Header
```

## Platform Channels

| Channel                         | Type           | Purpose                        |
|---------------------------------|----------------|--------------------------------|
| `metronome`                     | MethodChannel  | Commands: init, play, pause, stop, setBPM, setVolume, etc. |
| `metronome_tick`                | EventChannel   | Streams 0-based beat index per tick |

## Method Channel Contract

All methods receive arguments as a map. Audio data is sent as raw bytes
(`Uint8List` on Dart / `byte[]` on Android / `FlutterStandardTypedData` on
Darwin).

| Method             | Arguments                                                        |
|--------------------|------------------------------------------------------------------|
| `init`             | `mainFileBytes`, `accentedFileBytes`, `bpm`, `volume`, `enableTickCallback`, `timeSignature`, `sampleRate` |
| `play`             | —                                                                |
| `pause`            | —                                                                |
| `stop`             | —                                                                |
| `setBPM`           | `bpm`                                                            |
| `getBPM`           | — (returns `int`)                                                |
| `setVolume`        | `volume` (0.0–1.0 float, Dart converts from 0–100)              |
| `getVolume`        | — (returns `int` 0–100)                                         |
| `setTimeSignature` | `timeSignature`                                                  |
| `getTimeSignature` | — (returns `int`)                                                |
| `setAudioFile`     | `mainFileBytes`, `accentedFileBytes`                             |
| `isPlaying`        | — (returns `bool`)                                               |
| `destroy`          | —                                                                |

## Platform Implementation Details

### Darwin (iOS + macOS) — `Metronome.swift`

- Uses `AVAudioEngine` → `AVAudioPlayerNode` → `AVAudioMixerNode`.
- Audio bytes are written to a temp file and loaded as `AVAudioFile`
  (via the `convenience init(fromData:)` extension).
- `generateBuffer()` creates an `AVAudioPCMBuffer` with one bar of PCM
  float data and schedules it with `.loops`.
- Tick timer: `DispatchSourceTimer` computing beat index from elapsed
  sample time.
- iOS only: handles `interruptionNotification` and `routeChangeNotification`
  to survive Bluetooth headset changes.

### Android — `Metronome.java`

- Uses `AudioTrack` in `MODE_STREAM`, PCM 16-bit mono.
- `byteArrayToShortArray()` converts raw WAV bytes to `short[]`.
- `generateBuffer()` builds a `short[]` bar buffer.
- Playback runs on a dedicated thread writing the buffer in a loop.
- Tick events: `AudioTrack.setPositionNotificationPeriod()` +
  `onPeriodicNotification()`.

### Web — `metronome_web.dart`

- Uses `AudioContext`, `AudioBufferSourceNode`, `GainNode`.
- Lookahead scheduler pattern (`_schedule()` / `_scheduleBeat()`) with
  100ms lookahead and 50ms scheduling interval.
- Audio format conversion handles resampling and channel downmixing.

## Common Modification Scenarios

### Adding a new method to the public API

1. Add the method to `lib/metronome.dart` (delegates to platform).
2. Add an abstract method to `lib/metronome_platform_interface.dart`.
3. Implement in `lib/metronome_method_channel.dart` (invoke on channel).
4. Implement in `lib/metronome_web.dart`.
5. Handle the new method name in each native plugin:
   - `darwin/.../MetronomePlugin.swift` → `handle(_:result:)` switch.
   - `android/.../MetronomePlugin.java` → `onMethodCall()` switch.
6. Implement the actual logic in the native engine class.

### Changing audio processing

- Buffer generation lives in `generateBuffer()` on each platform.
- Beat length formula: `sampleRate * 60 / bpm` frames.
- Accented beat is always index 0 within the bar.

### Modifying the tick callback

- Darwin: `startBeatTimer()` / `stopBeatTimer()` in `Metronome.swift`.
- Android: `onTick()` in `Metronome.java` via `AudioTrack` listener.
- Web: `_scheduleBeat()` fires `tickController.add()` in source `onEnded`.
- Dart side: `EventChannel("metronome_tick")` → `tickController` stream
  in `metronome_method_channel.dart`.

## Volume Convention

Dart API uses **0–100 int**. Native engines expect **0.0–1.0 float**.
Conversion happens in `metronome_method_channel.dart` (`volume / 100.0`
on send, `* 100` on receive).
