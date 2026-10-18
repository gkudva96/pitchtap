import AVFoundation
import CoreAudio
import CPitchRing

/// Taps an app's audio (or all system audio) with a Core Audio process tap, which mutes the
/// original while tapped, runs it through `PitchGraph`, and plays the result on the default output
/// device. Main-thread only, except for the IOProc block.
final class TapEngine {
    enum Status: Equatable {
        case off
        case waiting(app: String)
        case active(output: String)
        /// `heardAudio`: whether anything has been captured since switching on. If not, the
        /// System Audio Recording permission is the likely cause.
        case silent(output: String, heardAudio: Bool)
        case failed(String)
    }

    var onStatus: ((Status) -> Void)?

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatus?(status) } }
    }

    /// Probe only: mix a sine of this amplitude into our output, to check that a system-wide tap
    /// doesn't capture PitchTap itself.
    var probeToneAmplitude: Float = 0

    var framesCaptured: UInt64 { pt_ring_total_written(ring) }

    private var enabled = false
    private var source = AudioSource.system
    private var params = PitchParams()

    private let ring: OpaquePointer = pt_ring_create(192_000)! // ≥ 1 s; the graph keeps it < 0.25 s
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var graph: PitchGraph?
    private var tapped: (source: AudioSource, processes: [AudioObjectID])?
    private var outputName = ""

    private var pollTimer: Timer?
    private var statusTimer: Timer?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var writtenAtEnable: UInt64 = 0
    private var lastWritten: UInt64 = 0
    private var lastAudioAt = Date()

    deinit {
        teardown()
        pt_ring_destroy(ring)
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            writtenAtEnable = pt_ring_total_written(ring)
            startWatching()
            reconcile()
        } else {
            stopWatching()
            teardown()
            status = .off
        }
    }

    func setSource(_ newSource: AudioSource) {
        guard newSource != source else { return }
        source = newSource
        reconcile()
    }

    func update(_ newParams: PitchParams) {
        params = newParams
        graph?.apply(newParams)
    }

    func shutdown() {
        setEnabled(false)
    }

    // MARK: - Watching for the source app and device changes

    private func startWatching() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        var addr = CA.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebuild(because: "default output changed")
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, listener)
    }

    private func stopWatching() {
        pollTimer?.invalidate()
        statusTimer?.invalidate()
        pollTimer = nil
        statusTimer = nil
        if let listener = outputListener {
            var addr = CA.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, listener)
            outputListener = nil
        }
    }

    private func rebuild(because reason: String) {
        guard enabled else { return }
        NSLog("PitchTap: \(reason), rebuilding")
        teardown()
        reconcile()
    }

    /// Builds, rebuilds or tears down the tap so it matches the source and its current processes.
    private func reconcile() {
        guard enabled else { return }
        let processes: [AudioObjectID]
        switch source {
        case .system: processes = []
        case let .app(bundleID, _): processes = AudioApps.processes(forBundleID: bundleID)
        }
        if let tapped, tapped.source == source, tapped.processes == processes, aggregateID != kAudioObjectUnknown {
            return
        }
        teardown()
        if case let .app(_, name) = source, processes.isEmpty {
            status = .waiting(app: name)
            return
        }
        do {
            try build(processes: processes)
            tapped = (source, processes)
            lastAudioAt = Date()
            status = .active(output: outputName)
        } catch {
            NSLog("PitchTap: \(error.localizedDescription)")
            teardown()
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Tap + aggregate device + IOProc

    private func makeTapDescription(processes: [AudioObjectID]) throws -> CATapDescription {
        guard case .system = source else {
            return CATapDescription(stereoMixdownOfProcesses: processes)
        }
        // Never tap our own output: it would loop straight back in.
        guard let me = AudioApps.ownProcessObject() else {
            throw CoreAudioError(status: kAudioHardwareUnspecifiedError,
                                 action: "find PitchTap's own audio process to exclude it from the system tap")
        }
        return CATapDescription(stereoGlobalTapButExcludeProcesses: [me])
    }

    private func build(processes: [AudioObjectID]) throws {
        let description = try makeTapDescription(processes: processes)
        description.uuid = UUID()
        description.name = "PitchTap"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create a process tap for \(source.name)")
        tapID = tap

        let outputDevice = try CA.defaultOutputDevice()
        let outputUID = try CA.readString(outputDevice, kAudioDevicePropertyDeviceUID)
        outputName = (try? CA.readString(outputDevice, kAudioObjectPropertyName)) ?? "output"

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PitchTap",
            kAudioAggregateDeviceUIDKey: "PitchTap-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg), "create the aggregate device")
        aggregateID = agg

        let tapFormat = try CA.read(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        guard tapFormat.mFormatID == kAudioFormatLinearPCM,
              tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              tapFormat.mBitsPerChannel == 32
        else {
            throw CoreAudioError(status: kAudioHardwareUnsupportedOperationError, action: "use the tap's audio format")
        }
        let tapPlanar = tapFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let sampleRate = try CA.read(agg, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))
        NSLog("PitchTap: tapping \(source.name) \(processes) at \(sampleRate) Hz (tap \(tapFormat.mSampleRate) Hz, " +
            "\(tapFormat.mChannelsPerFrame) ch, \(tapPlanar ? "planar" : "interleaved")) → \(outputName)")

        pt_ring_clear(ring)
        let graph = try PitchGraph(sampleRate: sampleRate, ring: ring)
        graph.apply(params)
        self.graph = graph

        let render = graph.engine.manualRenderingBlock
        let scratch = AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: PitchGraph.maxFrames)!
        let scratchList = scratch.mutableAudioBufferList
        let ring = self.ring
        let maxFrames = Int(PitchGraph.maxFrames)
        let toneAmplitude = probeToneAmplitude
        let toneStep = Float(2 * Double.pi * 440 / sampleRate)
        var tonePhase: Float = 0

        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, agg, nil) { _, inInput, _, outOutput, _ in
            // Input: the tap's stream(s) come after any input streams of the output device.
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            if tapPlanar, inputs.count >= 2,
               let l = inputs[inputs.count - 2].mData?.assumingMemoryBound(to: Float.self),
               let r = inputs[inputs.count - 1].mData?.assumingMemoryBound(to: Float.self) {
                let frames = Int(inputs[inputs.count - 1].mDataByteSize) / 4
                if !(pt_is_silent(l, frames) != 0 && pt_is_silent(r, frames) != 0) {
                    _ = pt_ring_write(ring, l, r, frames, 1)
                }
            } else if let last = inputs.last, let p = last.mData?.assumingMemoryBound(to: Float.self) {
                let channels = max(1, Int(last.mNumberChannels))
                let frames = Int(last.mDataByteSize) / (4 * channels)
                // Skip digital silence so the status can tell "nothing playing" apart.
                if pt_is_silent(p, frames * channels) == 0 {
                    _ = pt_ring_write(ring, p, channels > 1 ? p + 1 : p, frames, channels)
                }
            }

            // Output: render the graph and spread L/R over the output device's channels.
            let outputs = UnsafeMutableAudioBufferListPointer(outOutput)
            guard outputs.count > 0 else { return }
            let firstChannels = max(1, Int(outputs[0].mNumberChannels))
            let frames = Int(outputs[0].mDataByteSize) / (4 * firstChannels)
            let totalChannels = outputs.reduce(0) { $0 + Int($1.mNumberChannels) }
            let scratchBuffers = UnsafeMutableAudioBufferListPointer(scratchList)
            let left = scratchBuffers[0].mData!.assumingMemoryBound(to: Float.self)
            let right = scratchBuffers[1].mData!.assumingMemoryBound(to: Float.self)

            var done = 0
            while done < frames {
                let n = min(frames - done, maxFrames)
                for i in 0..<scratchBuffers.count { scratchBuffers[i].mDataByteSize = UInt32(n * 4) }
                var err: OSStatus = noErr
                if render(AVAudioFrameCount(n), scratchList, &err) != .success {
                    left.update(repeating: 0, count: n)
                    right.update(repeating: 0, count: n)
                }
                if toneAmplitude > 0 {
                    for f in 0..<n {
                        let s = toneAmplitude * sin(tonePhase)
                        left[f] += s
                        right[f] += s
                        tonePhase = (tonePhase + toneStep).truncatingRemainder(dividingBy: 2 * .pi)
                    }
                }
                var channelBase = 0
                for buffer in outputs {
                    let channels = Int(buffer.mNumberChannels)
                    guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                        channelBase += channels
                        continue
                    }
                    for c in 0..<channels {
                        let channel = channelBase + c
                        for f in 0..<n {
                            let sample: Float
                            if totalChannels == 1 { sample = 0.5 * (left[f] + right[f]) }
                            else if channel == 0 { sample = left[f] }
                            else if channel == 1 { sample = right[f] }
                            else { sample = 0 }
                            out[(done + f) * channels + c] = sample
                        }
                    }
                    channelBase += channels
                }
                done += n
            }
            withExtendedLifetime(scratch) {}
        }, "create the audio callback")
        ioProcID = proc
        try check(AudioDeviceStart(agg, proc), "start audio")
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let proc = ioProcID {
                AudioDeviceStop(aggregateID, proc)
                AudioDeviceDestroyIOProcID(aggregateID, proc)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        graph?.stop()
        graph = nil
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        tapped = nil
    }

    // MARK: - Status

    private func updateStatus() {
        guard enabled, graph != nil else { return }
        let written = pt_ring_total_written(ring)
        if written != lastWritten {
            lastWritten = written
            lastAudioAt = Date()
        }
        status = Date().timeIntervalSince(lastAudioAt) > 3
            ? .silent(output: outputName, heardAudio: written > writtenAtEnable)
            : .active(output: outputName)
    }
}
