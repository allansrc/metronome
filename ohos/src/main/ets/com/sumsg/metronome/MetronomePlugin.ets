import audio from '@ohos.multimedia.audio';
import { EventChannel } from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';

const METHOD_CHANNEL = 'metronome';
const TICK_CHANNEL = 'metronome_tick';
const TEMPO_RAMP_CHANNEL = 'metronome_tempo_ramp';

class Metronome {
  private renderer: audio.AudioRenderer | null = null;
  private mainSound: ArrayBuffer = new ArrayBuffer(0);
  private accentedSound: ArrayBuffer = new ArrayBuffer(0);
  private audioBuffer: ArrayBuffer | null = null;
  private audioDataOffset: number = 0;
  private eventTickSink: EventSink | null = null;
  private playing: boolean = false;
  private updated: boolean = true;
  private playbackToken: number = 0;
  private eventTempoRampSink: EventSink | null = null;
  private rampEnabled: boolean = false;
  private rampStatus: string = 'idle';
  private rampStartBpm: number = 0;
  private rampTargetBpm: number = 0;
  private rampStepBpm: number = 0;
  private rampMeasuresPerStep: number = 0;
  private rampStageIndex: number = 0;
  private rampCompletedMeasures: number = 0;

  public audioBpm: number;
  public audioTimeSignature: number;
  public audioVolume: number;
  private readonly sampleRate: number;
  private tickCallbackEnabled: boolean = false;

  constructor(mainFileBytes: ArrayBuffer, accentedFileBytes: ArrayBuffer, bpm: number,
    timeSignature: number, volume: number, sampleRate: number, sink: EventSink | null) {
    this.mainSound = mainFileBytes;
    this.accentedSound = accentedFileBytes.byteLength === 0 ? mainFileBytes : accentedFileBytes;
    this.audioBpm = bpm;
    this.audioTimeSignature = timeSignature;
    this.audioVolume = volume;
    this.sampleRate = sampleRate;
    this.eventTickSink = sink;
  }

  setTickSink(sink: EventSink | null): void {
    this.eventTickSink = sink;
  }

  setTempoRampSink(sink: EventSink | null): void {
    this.eventTempoRampSink = sink;
    if (this.rampEnabled) this.emitRampProgress();
  }

  async init(enableTickCallback: boolean): Promise<void> {
    await this.releaseRenderer();
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: this.sampleRate as audio.AudioSamplingRate,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const rendererInfo: audio.AudioRendererInfo = {
      content: audio.ContentType.CONTENT_TYPE_MUSIC,
      usage: audio.StreamUsage.STREAM_USAGE_MEDIA,
      rendererFlags: 0
    };
    const options: audio.AudioRendererOptions = { streamInfo, rendererInfo };
    this.renderer = await audio.createAudioRenderer(options);
    await this.renderer.setVolume(this.audioVolume);
    this.tickCallbackEnabled = enableTickCallback;
    this.updated = true;
    this.configureTickCallback();
    this.configureWriteCallback();
  }

  async play(): Promise<void> {
    if (this.renderer === null || this.playing) {
      return;
    }
    this.playing = true;
    this.tick = 0;
    this.playbackToken++;
    try {
      await this.renderer.start();
    } catch (error) {
      this.playing = false;
      throw new Error(String(error));
    }
    this.eventTickSink?.success(0);
    if (this.rampEnabled && this.rampStatus !== 'completed') {
      this.rampStatus = 'running';
      this.emitRampProgress();
    }
  }

  async pause(): Promise<void> {
    if (this.renderer === null || !this.playing) {
      return;
    }
    this.playing = false;
    this.playbackToken++;
    await this.renderer.pause();
    if (this.rampEnabled && this.rampStatus === 'running') {
      this.rampStatus = 'paused';
      this.emitRampProgress();
    }
  }

  async stop(): Promise<void> {
    if (this.renderer === null) {
      return;
    }
    this.playing = false;
    this.playbackToken++;
    if (this.renderer.state === audio.AudioState.STATE_RUNNING ||
      this.renderer.state === audio.AudioState.STATE_PAUSED) {
      await this.renderer.stop();
    }
    this.audioBuffer = null;
    this.audioDataOffset = 0;
    this.updated = true;
    if (this.rampEnabled) this.resetRamp();
  }

  async setVolume(volume: number): Promise<void> {
    this.audioVolume = volume;
    if (this.renderer !== null) {
      await this.renderer.setVolume(volume);
    }
  }

  isPlaying(): boolean {
    return this.playing;
  }

  async setBPM(bpm: number): Promise<void> {
    if (this.rampEnabled) this.disableTempoRamp();
    this.audioBpm = bpm;
    this.configureTickCallback();
    if (this.playing) {
      await this.restart();
    }
  }

  configureTempoRamp(startBpm: number, targetBpm: number, stepBpm: number, measuresPerStep: number): void {
    if (this.playing) {
      throw new Error('Pause or stop before configuring a tempo ramp');
    }
    this.rampEnabled = true;
    this.rampStartBpm = startBpm;
    this.rampTargetBpm = targetBpm;
    this.rampStepBpm = stepBpm;
    this.rampMeasuresPerStep = measuresPerStep;
    this.resetRamp();
  }

  disableTempoRamp(): void {
    this.rampEnabled = false;
    this.rampStatus = 'idle';
    this.rampStageIndex = 0;
    this.rampCompletedMeasures = 0;
    this.emitRampProgress();
  }

  async setTimeSignature(timeSignature: number): Promise<void> {
    this.audioTimeSignature = timeSignature;
    this.updated = true;
    if (this.playing) {
      await this.restart();
    }
  }

  async setAudioFile(mainFileBytes: ArrayBuffer, accentedFileBytes: ArrayBuffer): Promise<void> {
    if (mainFileBytes.byteLength > 0) {
      this.mainSound = mainFileBytes;
    }
    if (accentedFileBytes.byteLength > 0) {
      this.accentedSound = accentedFileBytes;
    }
    this.updated = true;
    if (this.playing) {
      await this.restart();
    }
  }

  async destroy(): Promise<void> {
    this.playing = false;
    this.playbackToken++;
    await this.releaseRenderer();
  }

  private async restart(): Promise<void> {
    await this.stop();
    await this.play();
  }

  private configureTickCallback(): void {
    if (this.renderer === null || !this.tickCallbackEnabled) {
      return;
    }
    this.renderer.off('periodReach');
    const framesPerBeat = Math.floor(this.sampleRate * 60 / this.audioBpm);
    this.renderer.on('periodReach', framesPerBeat, () => {
      if (this.audioTimeSignature < 2) {
        this.eventTickSink?.success(0);
        return;
      }
      this.tick = (this.tick + 1) % this.audioTimeSignature;
      this.eventTickSink?.success(this.tick);
    });
  }

  private tick: number = 0;

  private generateBuffer(): ArrayBuffer {
    const framesPerBeat = Math.floor(this.sampleRate * 60 / this.audioBpm);
    const beats = this.audioTimeSignature < 2 ? 1 : this.audioTimeSignature;
    const buffer = new Uint8Array(framesPerBeat * beats * 2);
    for (let beat = 0; beat < beats; beat++) {
      const sound = beat === 0 && beats > 1 ? this.accentedSound : this.mainSound;
      const source = new Uint8Array(sound).subarray(sound.byteLength > 44 ? 44 : 0);
      const offset = beat * framesPerBeat * 2;
      buffer.set(source.subarray(0, Math.min(source.length, framesPerBeat * 2)), offset);
    }
    return buffer.buffer;
  }

  private configureWriteCallback(): void {
    if (this.renderer === null) {
      return;
    }
    this.renderer.off('writeData');
    this.renderer.on('writeData', (data: ArrayBuffer): audio.AudioDataCallbackResult => {
      const target = new Uint8Array(data);
      if (!this.playing) {
        target.fill(0);
        return audio.AudioDataCallbackResult.INVALID;
      }
      if (this.updated || this.audioBuffer === null) {
        this.audioBuffer = this.generateBuffer();
        this.audioDataOffset = 0;
        this.updated = false;
      }
      if (this.audioBuffer.byteLength === 0) {
        target.fill(0);
        return audio.AudioDataCallbackResult.INVALID;
      }
      for (let offset = 0; offset < target.length;) {
        const bytes = new Uint8Array(this.audioBuffer!);
        const count = Math.min(bytes.length - this.audioDataOffset, target.length - offset);
        target.set(bytes.subarray(this.audioDataOffset, this.audioDataOffset + count), offset);
        offset += count;
        this.audioDataOffset = (this.audioDataOffset + count) % bytes.length;
        if (this.audioDataOffset === 0) this.completeRampMeasure();
      }
      return audio.AudioDataCallbackResult.VALID;
    });
  }

  private completeRampMeasure(): void {
    if (!this.rampEnabled || this.rampStatus !== 'running') return;
    this.rampCompletedMeasures++;
    if (this.rampCompletedMeasures >= this.rampMeasuresPerStep) {
      this.rampCompletedMeasures = 0;
      this.audioBpm = Math.min(this.audioBpm + this.rampStepBpm, this.rampTargetBpm);
      this.rampStageIndex++;
      this.audioBuffer = this.generateBuffer();
      this.configureTickCallback();
      if (this.audioBpm >= this.rampTargetBpm) this.rampStatus = 'completed';
    }
    this.emitRampProgress();
  }

  private resetRamp(): void {
    this.audioBpm = this.rampStartBpm;
    this.rampStatus = 'armed';
    this.rampStageIndex = 0;
    this.rampCompletedMeasures = 0;
    this.audioDataOffset = 0;
    this.updated = true;
    this.configureTickCallback();
    this.emitRampProgress();
  }

  private emitRampProgress(): void {
    const totalStages = this.rampEnabled
      ? Math.ceil((this.rampTargetBpm - this.rampStartBpm) / this.rampStepBpm) + 1
      : 0;
    this.eventTempoRampSink?.success({
      status: this.rampStatus,
      currentBpm: this.rampEnabled ? this.audioBpm : 0,
      stageIndex: this.rampStageIndex,
      completedMeasures: this.rampCompletedMeasures,
      totalStages
    });
  }

  private async releaseRenderer(): Promise<void> {
    if (this.renderer === null) {
      return;
    }
    const renderer = this.renderer;
    this.renderer = null;
    this.playing = false;
    if (renderer.state === audio.AudioState.STATE_RUNNING ||
      renderer.state === audio.AudioState.STATE_PAUSED) {
      await renderer.stop();
    }
    if (renderer.state !== audio.AudioState.STATE_RELEASED &&
      renderer.state !== audio.AudioState.STATE_NEW) {
      await renderer.release();
    }
  }
}

export default class MetronomePlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private eventTick: EventChannel | null = null;
  private eventTempoRamp: EventChannel | null = null;
  private eventTempoRampSink: EventSink | null = null;
  private eventTickSink: EventSink | null = null;
  private metronome: Metronome | null = null;

  getUniqueClassName(): string {
    return 'MetronomePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
    this.channel.setMethodCallHandler(this);
    this.eventTick = new EventChannel(binding.getBinaryMessenger(), TICK_CHANNEL);
    this.eventTick.setStreamHandler(new StreamHandlerImpl(this));
    this.eventTempoRamp = new EventChannel(binding.getBinaryMessenger(), TEMPO_RAMP_CHANNEL);
    this.eventTempoRamp.setStreamHandler(new TempoRampStreamHandlerImpl(this));
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.eventTick?.setStreamHandler(null);
    this.eventTempoRamp?.setStreamHandler(null);
    this.metronome?.destroy().catch(() => undefined);
    this.channel = null;
    this.eventTick = null;
    this.eventTempoRamp = null;
    this.metronome = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handleMethodCall(call, result).catch((error: Error) => {
      result.error('METRONOME_ERROR', error.message, null);
    });
  }

  private async handleMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'init': {
        const args = call.args as Map<string, Object>;
        await this.metronome?.destroy();
        const metronome = new Metronome(
          this.bytes(args.get('mainFileBytes')),
          this.bytes(args.get('accentedFileBytes')),
          Number(args.get('bpm') ?? 120),
          Number(args.get('timeSignature') ?? 4),
          Number(args.get('volume') ?? 0.5),
          Number(args.get('sampleRate') ?? 44100),
          this.eventTickSink
        );
        await metronome.init(Boolean(args.get('enableTickCallback')));
        metronome.setTempoRampSink(this.eventTempoRampSink);
        this.metronome = metronome;
        result.success(null);
        return;
      }
      case 'play':
        await this.requireMetronome().play();
        result.success(null);
        return;
      case 'pause':
        await this.requireMetronome().pause();
        result.success(null);
        return;
      case 'stop':
        await this.requireMetronome().stop();
        result.success(null);
        return;
      case 'getVolume':
        result.success(Math.round(this.requireMetronome().audioVolume * 100));
        return;
      case 'setVolume':
        await this.requireMetronome().setVolume(Number((call.args as Map<string, Object>).get('volume')));
        result.success(null);
        return;
      case 'isPlaying':
        result.success(this.requireMetronome().isPlaying());
        return;
      case 'setBPM':
        await this.requireMetronome().setBPM(Number((call.args as Map<string, Object>).get('bpm')));
        result.success(null);
        return;
      case 'getBPM':
        result.success(this.requireMetronome().audioBpm);
        return;
      case 'configureTempoRamp': {
        const args = call.args as Map<string, Object>;
        this.requireMetronome().configureTempoRamp(
          Number(args.get('startBpm')),
          Number(args.get('targetBpm')),
          Number(args.get('stepBpm')),
          Number(args.get('measuresPerStep'))
        );
        result.success(null);
        return;
      }
      case 'disableTempoRamp':
        this.requireMetronome().disableTempoRamp();
        result.success(null);
        return;
      case 'setTimeSignature':
        await this.requireMetronome().setTimeSignature(
          Number((call.args as Map<string, Object>).get('timeSignature'))
        );
        result.success(null);
        return;
      case 'getTimeSignature':
        result.success(this.requireMetronome().audioTimeSignature);
        return;
      case 'setAudioFile': {
        const args = call.args as Map<string, Object>;
        await this.requireMetronome().setAudioFile(
          this.bytes(args.get('mainFileBytes')),
          this.bytes(args.get('accentedFileBytes'))
        );
        result.success(null);
        return;
      }
      case 'destroy':
        await this.requireMetronome().destroy();
        this.metronome = null;
        result.success(null);
        return;
      default:
        result.notImplemented();
    }
  }

  private requireMetronome(): Metronome {
    if (this.metronome === null) {
      throw new Error('Metronome has not been initialized');
    }
    return this.metronome;
  }

  private bytes(value: Object | undefined): ArrayBuffer {
    if (value instanceof ArrayBuffer) {
      return value;
    }
    if (value instanceof Uint8Array) {
      return value.buffer;
    }
    return new ArrayBuffer(0);
  }

  setTickSink(sink: EventSink | null): void {
    this.eventTickSink = sink;
    this.metronome?.setTickSink(sink);
  }

  setTempoRampSink(sink: EventSink | null): void {
    this.eventTempoRampSink = sink;
    this.metronome?.setTempoRampSink(sink);
  }
}

class StreamHandlerImpl implements StreamHandler {
  private readonly plugin: MetronomePlugin;

  constructor(plugin: MetronomePlugin) {
    this.plugin = plugin;
  }

  onListen(args: Object, events: EventSink): void {
    this.plugin.setTickSink(events);
  }

  onCancel(args: Object): void {
    this.plugin.setTickSink(null);
  }
}

class TempoRampStreamHandlerImpl implements StreamHandler {
  private readonly plugin: MetronomePlugin;

  constructor(plugin: MetronomePlugin) {
    this.plugin = plugin;
  }

  onListen(args: Object, events: EventSink): void {
    this.plugin.setTempoRampSink(events);
  }

  onCancel(args: Object): void {
    this.plugin.setTempoRampSink(null);
  }
}
