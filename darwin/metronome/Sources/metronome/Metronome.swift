import AVFoundation

class Metronome {
    private var eventTick: EventTickHandler?
    private var audioPlayerNode: AVAudioPlayerNode = AVAudioPlayerNode()
    private var audioEngine: AVAudioEngine = AVAudioEngine()
    private var mixerNode: AVAudioMixerNode
    private var audioBuffer: AVAudioPCMBuffer?
    //
    private var audioFileMain: AVAudioFile
    private var audioFileAccented: AVAudioFile
    public var audioBpm: Int = 120
    public var audioVolume: Float = 0.5
    /// Group sizes per bar; first beat of each group uses the accented sound.
    public var accentPattern: [Int] = [4]

    private var sampleRate: Int = 44100

    private var totalBeats: Int {
        accentPattern.reduce(0, +)
    }

    private func isAccentBeat(_ index: Int) -> Bool {
        var pos = 0
        for group in accentPattern {
            if index == pos { return true }
            pos += group
        }
        return false
    }
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.metronome.beat-timer", qos: .background)
    private var eventTempoRamp: EventTempoRampHandler?
    private var rampEnabled = false
    private var rampStatus = "idle"
    private var rampStartBpm = 0
    private var rampTargetBpm = 0
    private var rampStepBpm = 0
    private var rampMeasuresPerStep = 0
    private var rampStageIndex = 0
    private var rampCompletedMeasures = 0
    private var playbackToken = 0
    /// Initialize the metronome with the main and accented audio files.
    init(
        mainFileBytes: Data, 
        accentedFileBytes: Data, 
        bpm: Int, 
        accentPattern: [Int], 
        volume: Float, 
        sampleRate: Int, 
        manageAudioSession: Bool = true
    ) {
        self.sampleRate = sampleRate
        self.accentPattern = accentPattern.isEmpty ? [4] : accentPattern
        audioBpm = bpm
        audioVolume = volume
        // Initialize audio files
        audioFileMain = try! AVAudioFile(fromData: mainFileBytes)
        if accentedFileBytes.isEmpty {
            audioFileAccented = audioFileMain
        }else{
            audioFileAccented = try! AVAudioFile(fromData: accentedFileBytes)
        }
#if os(iOS)
        if manageAudioSession {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .videoRecording,
                    options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
                )

                try audioSession.setActive(true)
            } catch {
                print("Failed to set audio session category: \(error)")
            }
        }
#endif
        // Initialize audio engine and player node
        audioEngine.attach(audioPlayerNode)
        // Set up mixer node
        mixerNode = audioEngine.mainMixerNode
        mixerNode.outputVolume = audioVolume
        // Connect nodes
        audioEngine.connect(audioPlayerNode, to: mixerNode, format: audioFileMain.processingFormat)
        audioEngine.prepare()
        // Start the audio engine
        if !self.audioEngine.isRunning {
            do {
                try self.audioEngine.start()
                print("Start the audio engine")
            } catch {
                print("Failed to start audio engine: \(error.localizedDescription)")
            }
        }
        // Set volume
        setVolume(volume:volume)
#if os(iOS)
        setupNotifications()
#endif
    }
    private func reconnectPlayerNode() {
        if !audioEngine.outputConnectionPoints(for: audioPlayerNode, outputBus: 0).isEmpty {
            audioEngine.disconnectNodeOutput(audioPlayerNode)
        }
        audioEngine.connect(audioPlayerNode, to: mixerNode, format: audioFileMain.processingFormat)
    }

    /// Start the metronome.
    func play() {
        if isPlaying { return }
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Audio engine failed to start in play(): \(error)")
                return
            }
        }
        playbackToken += 1
        if rampEnabled {
            if rampStatus != "completed" { rampStatus = "running" }
            scheduleRampMeasure(token: playbackToken)
            emitRampProgress()
        } else {
            audioBuffer = generateBuffer()
        }
    }

    /// Pause the metronome.
    func pause() {
        stopPlayback()
        if rampEnabled && rampStatus == "running" {
            rampStatus = "paused"
            emitRampProgress()
        }
    }
    
    /// Stop the metronome.
    func stop() {
        stopPlayback()
        if rampEnabled { resetRamp() }
    }

    private func stopPlayback() {
        playbackToken += 1
        // Stop the beat callback before operating on the player node.
        stopBeatTimer()
        if audioBuffer != nil {
            audioBuffer?.frameLength = 0
            self.audioPlayerNode.scheduleBuffer(audioBuffer!, at: nil, options: .interruptsAtLoop, completionHandler: nil)
        }
        audioPlayerNode.stop()
    }
    
    /// Set the BPM of the metronome.
    func setBPM(bpm: Int) {
        if rampEnabled { disableTempoRamp() }
        if audioBpm != bpm {
            audioBpm = bpm
            if isPlaying {
                pause()
                play()
            }
        }
    }
    func setAccentPattern(accentPattern newPattern: [Int]) {
        let normalized = newPattern.isEmpty ? [4] : newPattern
        if accentPattern != normalized {
            accentPattern = normalized
            if isPlaying {
                pause()
                play()
            }
        }
    }
    
    func setAudioFile(mainFileBytes: Data, accentedFileBytes: Data) {
        if mainFileBytes.isEmpty && accentedFileBytes.isEmpty { return }

        let wasPlaying = isPlaying
        if wasPlaying { stop() }

        if !mainFileBytes.isEmpty {
            audioFileMain = try! AVAudioFile(fromData: mainFileBytes)
        }
        if !accentedFileBytes.isEmpty {
            audioFileAccented = try! AVAudioFile(fromData: accentedFileBytes)
        }

        reconnectPlayerNode()

        if wasPlaying { play() }
    }
    
    var getVolume: Int {
        return Int(audioVolume * 100)
    }
    
    func setVolume(volume: Float) {
        audioVolume = volume
        mixerNode.outputVolume = volume
    }
    
    var isPlaying: Bool {
        return audioPlayerNode.isPlaying
    }
    
    /// Enable the tick callback.
    public func enableTickCallback(_eventTickSink: EventTickHandler) {
        self.eventTick = _eventTickSink
    }

    public func enableTempoRampCallback(_ eventSink: EventTempoRampHandler) {
        eventTempoRamp = eventSink
        if rampEnabled { emitRampProgress() }
    }

    func configureTempoRamp(startBpm: Int, targetBpm: Int, stepBpm: Int, measuresPerStep: Int) {
        rampEnabled = true
        rampStartBpm = startBpm
        rampTargetBpm = targetBpm
        rampStepBpm = stepBpm
        rampMeasuresPerStep = measuresPerStep
        resetRamp()
    }

    func disableTempoRamp() {
        let wasPlaying = isPlaying
        rampEnabled = false
        rampStatus = "idle"
        rampStageIndex = 0
        rampCompletedMeasures = 0
        emitRampProgress()
        if wasPlaying {
            let buffer = buildBuffer()
            audioBuffer = buffer
            audioPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        }
    }
#if os(iOS)
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main,
            using: handleInterruption
        )
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main,
            using: handleRouteChange
        )
    }

    private func handleInterruption(_ notification: Notification) {
        if isPlaying {
            pause()
        }
    }
    private func handleRouteChange(_ notification: Notification) {
        let wasPlaying = isPlaying
        if wasPlaying {
            self.stop()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.audioEngine.stop()

            do {
                try self.audioEngine.start()
            } catch {
                print("Audio engine failed to restart: \(error.localizedDescription)")
            }

            if wasPlaying {
                self.play()
            }
        }
    }
#endif
    /// Generate buffer with accents based on time signature
    private func buildBuffer() -> AVAudioPCMBuffer {
        audioFileMain.framePosition = 0
        audioFileAccented.framePosition = 0

        let beatLength = AVAudioFrameCount(Double(self.sampleRate) * 60 / Double(self.audioBpm))
        // let beatLength = AVAudioFrameCount(audioFileMain.processingFormat.sampleRate * 60 / Double(self.audioBpm))
        let bufferMainClick = AVAudioPCMBuffer(pcmFormat: audioFileMain.processingFormat, frameCapacity: beatLength)!
        try! audioFileMain.read(into: bufferMainClick)
        bufferMainClick.frameLength = beatLength

        let bufferBar: AVAudioPCMBuffer
        let beats = totalBeats
        if beats < 2 {
            bufferBar = AVAudioPCMBuffer(pcmFormat: audioFileMain.processingFormat, frameCapacity: beatLength)!
            bufferBar.frameLength = beatLength

            let channelCount = Int(audioFileMain.processingFormat.channelCount)
            let mainClickArray = Array(UnsafeBufferPointer(start: bufferMainClick.floatChannelData![0], count: channelCount * Int(beatLength)))

            bufferBar.floatChannelData!.pointee.update(from: mainClickArray, count: channelCount * Int(bufferBar.frameLength))
        } else {
            let bufferAccentedClick = AVAudioPCMBuffer(pcmFormat: audioFileAccented.processingFormat, frameCapacity: beatLength)!
            try! audioFileAccented.read(into: bufferAccentedClick)
            bufferAccentedClick.frameLength = beatLength

            bufferBar = AVAudioPCMBuffer(pcmFormat: audioFileMain.processingFormat, frameCapacity: beatLength * AVAudioFrameCount(beats))!
            bufferBar.frameLength = beatLength * AVAudioFrameCount(beats)

            let channelCount = Int(audioFileMain.processingFormat.channelCount)
            let mainClickArray = Array(UnsafeBufferPointer(start: bufferMainClick.floatChannelData![0], count: channelCount * Int(beatLength)))
            let accentedClickArray = Array(UnsafeBufferPointer(start: bufferAccentedClick.floatChannelData![0], count: channelCount * Int(beatLength)))

            var barArray = [Float]()
            for i in 0..<beats {
                if isAccentBeat(i) {
                    barArray.append(contentsOf: accentedClickArray)
                } else {
                    barArray.append(contentsOf: mainClickArray)
                }
            }

            bufferBar.floatChannelData!.pointee.update(from: barArray, count: channelCount * Int(bufferBar.frameLength))
        }
        return bufferBar
    }

    private func generateBuffer() -> AVAudioPCMBuffer {
        let bufferBar = buildBuffer()
        self.audioPlayerNode.scheduleBuffer(bufferBar, at: nil, options: .loops, completionHandler: nil)
        self.audioPlayerNode.play()
        startBeatTimer()
        return bufferBar
    }

    private func scheduleRampMeasure(token: Int) {
        guard rampEnabled && token == playbackToken else { return }
        let buffer = buildBuffer()
        audioBuffer = buffer
        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard let self = self, token == self.playbackToken, self.audioPlayerNode.isPlaying else { return }
            self.completeRampMeasure()
            self.scheduleRampMeasure(token: token)
        }
        if !audioPlayerNode.isPlaying {
            audioPlayerNode.play()
            startBeatTimer()
        }
    }

    private func completeRampMeasure() {
        guard rampEnabled && rampStatus == "running" else { return }
        rampCompletedMeasures += 1
        if rampCompletedMeasures >= rampMeasuresPerStep {
            rampCompletedMeasures = 0
            audioBpm = min(audioBpm + rampStepBpm, rampTargetBpm)
            rampStageIndex += 1
            stopBeatTimer()
            startBeatTimer()
            if audioBpm >= rampTargetBpm { rampStatus = "completed" }
        }
        emitRampProgress()
    }

    private func resetRamp() {
        audioBpm = rampStartBpm
        rampStatus = "armed"
        rampStageIndex = 0
        rampCompletedMeasures = 0
        emitRampProgress()
    }

    private var totalRampStages: Int {
        return ((rampTargetBpm - rampStartBpm + rampStepBpm - 1) / rampStepBpm) + 1
    }

    private func emitRampProgress() {
        eventTempoRamp?.send(res: [
            "status": rampStatus,
            "currentBpm": rampEnabled ? audioBpm : 0,
            "stageIndex": rampStageIndex,
            "completedMeasures": rampCompletedMeasures,
            "totalStages": rampEnabled ? totalRampStages : 0,
        ])
    }
    
    func stopBeatTimer() {
        if timer != nil {
            timer?.cancel()
            timer = nil
        }
    }
    
    private func startBeatTimer() {
        if self.eventTick == nil {return}
        let beatDuration = 60.0 / Double(audioBpm)
        let startUptime = DispatchTime.now().uptimeNanoseconds
        timer?.cancel()
        timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer?.schedule(deadline: .now(), repeating: beatDuration, leeway: .milliseconds(10))
        timer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Use a monotonic clock to decouple the beat callback from the AVAudioNode lifecycle.
            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startUptime
            let elapsedTime = Double(elapsedNanoseconds) / 1_000_000_000

            let currentBeat = Int(elapsedTime / beatDuration)
            let tb = self.totalBeats
            let currentTick = (tb > 1) ? (currentBeat % tb) : 0

            DispatchQueue.main.async {
                self.eventTick?.send(res: currentTick)
            }
        }

        timer?.resume()
    }

    func destroy() {
        // Stop the beat callback before operating on the player node.
        stopBeatTimer()
        audioPlayerNode.stop()
        audioPlayerNode.reset()
        audioEngine.stop()
        audioEngine.reset()
        if audioEngine.attachedNodes.contains(audioPlayerNode) {
            audioEngine.detach(audioPlayerNode)
        }
        audioBuffer = nil
    }
}
extension AVAudioFile {
    convenience init(fromData data: Data) throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try data.write(to: tempURL)
            //print("Temporary file created at: \(tempURL)")
        } catch {
            //print("Failed to write data to temporary file: \(error.localizedDescription)")
            throw error
        }
        do {
            try self.init(forReading: tempURL)
        } catch {
            //print("Failed to initialize AVAudioFile: \(error.localizedDescription)")
            throw error
        }
    }
}
