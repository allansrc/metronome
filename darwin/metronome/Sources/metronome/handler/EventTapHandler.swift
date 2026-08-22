#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
class EventTickHandler: NSObject,FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    
    public func send(res:Int){
        if let event = eventSink {
            event(res)
        }
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // if let arguments = arguments {
        //     print("StreamHandler - onListen: \(arguments)")
        // }
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
//        if let arguments = arguments {
//            print("StreamHandler - onCancel: \(arguments)")
//        }
        eventSink = nil
        return nil
    }
}

class EventTempoRampHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    public func send(res: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(res)
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
