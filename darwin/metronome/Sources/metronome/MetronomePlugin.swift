#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
// import Cocoa
#endif
public class MetronomePlugin: NSObject, FlutterPlugin {
    var channel:FlutterMethodChannel?
    var metronome:Metronome?
    //
    private let eventTickListener: EventTickHandler = EventTickHandler()
    private var eventTick: FlutterEventChannel?
    private let eventTempoRampListener = EventTempoRampHandler()
    private var eventTempoRamp: FlutterEventChannel?
    //
    init(with registrar: FlutterPluginRegistrar) {}
    //
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MetronomePlugin(with: registrar)
#if os(iOS)
    let messenger = registrar.messenger()
#else
    let messenger = registrar.messenger
#endif
        instance.channel = FlutterMethodChannel(name: "metronome", binaryMessenger: messenger)

        registrar.addApplicationDelegate(instance)
        registrar.addMethodCallDelegate(instance, channel: instance.channel!)
        //
        instance.eventTick = FlutterEventChannel(name: "metronome_tick", binaryMessenger: messenger)
        instance.eventTick?.setStreamHandler(instance.eventTickListener )
        instance.eventTempoRamp = FlutterEventChannel(name: "metronome_tempo_ramp", binaryMessenger: messenger)
        instance.eventTempoRamp?.setStreamHandler(instance.eventTempoRampListener)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
          let attributes = call.arguments as? NSDictionary
          switch call.method {
              case "init":
                  metronomeInit(attributes: attributes)
                  result(nil)
                  return
              case "play":
                  metronome?.play()
                  result(nil)
                  return
              case "pause":
                  metronome?.pause()
                  result(nil)
                  return
              case "stop":
                  metronome?.stop()
                  result(nil)
                  return
              case "getVolume":
                  result(metronome?.getVolume)
                break;
              case "setVolume":
                  setVolume(attributes: attributes)
                  result(nil)
                  return
              case "isPlaying":
                  result(metronome?.isPlaying)
                break;
              case "setBPM":
                  setBPM(attributes: attributes)
                  result(nil)
                  return
              case "configureTempoRamp":
                  guard let metronome = metronome else {
                      result(FlutterError(code: "not_initialized", message: "Metronome has not been initialized", details: nil))
                      return
                  }
                  if metronome.isPlaying {
                      result(FlutterError(code: "ramp_while_playing", message: "Pause or stop before configuring a tempo ramp", details: nil))
                      return
                  }
                  let startBpm = attributes?["startBpm"] as? Int ?? 0
                  let targetBpm = attributes?["targetBpm"] as? Int ?? 0
                  let stepBpm = attributes?["stepBpm"] as? Int ?? 0
                  let measuresPerStep = attributes?["measuresPerStep"] as? Int ?? 0
                  guard startBpm > 0, targetBpm > startBpm, stepBpm > 0, measuresPerStep > 0 else {
                      result(FlutterError(code: "invalid_ramp_config", message: "Invalid tempo ramp configuration", details: nil))
                      return
                  }
                  metronome.configureTempoRamp(
                      startBpm: startBpm,
                      targetBpm: targetBpm,
                      stepBpm: stepBpm,
                      measuresPerStep: measuresPerStep
                  )
                  result(nil)
                  return
              case "disableTempoRamp":
                  metronome?.disableTempoRamp()
                  result(nil)
                  return
              case "getBPM":
                  result(metronome?.audioBpm)
                break;
              case "setTimeSignature":
                  setTimeSignature(attributes: attributes)
                  result(nil)
                  return
              case "getTimeSignature":
                  result(metronome?.audioTimeSignature)
                break;
              case "setAudioFile":
                  setAudioFile(attributes: attributes)
                  result(nil)
                  return
              case "destroy":
                  metronome?.destroy()
                  result(nil)
                  return
              default:
                  result("unkown")
                break;
        }
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        channel?.setMethodCallHandler(nil)
        eventTick?.setStreamHandler(nil)
        eventTempoRamp?.setStreamHandler(nil)
    }
    private func setBPM( attributes:NSDictionary?) {
        if metronome != nil {
            let bpm: Int = (attributes?["bpm"] as? Int) ?? 120
            metronome?.setBPM(bpm: bpm)
        }
    }
    private func setTimeSignature( attributes:NSDictionary?) {
        if metronome != nil {
            let timeSignature: Int = (attributes?["timeSignature"] as? Int) ?? 0
            metronome?.setTimeSignature(timeSignature: timeSignature)
        }
    }
    private func metronomeInit( attributes:NSDictionary?) {
        let mainFileBytes = (attributes?["mainFileBytes"] as? FlutterStandardTypedData) ?? FlutterStandardTypedData()
        let accentedFileBytes = (attributes?["accentedFileBytes"] as? FlutterStandardTypedData) ?? FlutterStandardTypedData()
        let mainBytes: Data = mainFileBytes.data
        let accentedBytes: Data = accentedFileBytes.data
        
        let enableTickCallback: Bool = (attributes?["enableTickCallback"] as? Bool) ?? true
        let timeSignature: Int = (attributes?["timeSignature"] as? Int) ?? 0
        let bpm: Int = (attributes?["bpm"] as? Int) ?? 120
        let volume: Float = (attributes?["volume"] as? Float) ?? 0.5
        let sampleRate: Int = (attributes?["sampleRate"] as? Int) ?? 44100
        // 默认保持插件原有行为；宿主已统一管理音频会话时可显式关闭。
        let manageAudioSession: Bool = (attributes?["manageAudioSession"] as? Bool) ?? true
        metronome = Metronome(
            mainFileBytes: mainBytes,
            accentedFileBytes: accentedBytes,
            bpm: bpm,
            timeSignature: timeSignature,
            volume: volume,
            sampleRate: sampleRate,
            manageAudioSession: manageAudioSession
        )
        metronome?.enableTempoRampCallback(eventTempoRampListener)
        if(enableTickCallback){
            metronome?.enableTickCallback(_eventTickSink: eventTickListener);
        }
    }
    private func setAudioFile( attributes:NSDictionary?) {
        if metronome != nil {
            let mainFileBytes = (attributes?["mainFileBytes"] as? FlutterStandardTypedData) ?? FlutterStandardTypedData()
            let accentedFileBytes = (attributes?["accentedFileBytes"] as? FlutterStandardTypedData) ?? FlutterStandardTypedData()
            let mainBytes: Data = mainFileBytes.data
            let accentedBytes: Data = accentedFileBytes.data
            metronome?.setAudioFile( mainFileBytes:mainBytes,accentedFileBytes: accentedBytes)
        }
    }
    private func setVolume( attributes:NSDictionary?) {
        if metronome != nil {
            let volume: Double = (attributes?["volume"] as? Double) ?? 0.5
            metronome?.setVolume(volume: Float(volume))
        }
    }
}
