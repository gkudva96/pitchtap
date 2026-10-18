import AVFoundation
import CPitchRing

/// The DSP chain: ring buffer → TimePitch → output, driven by manual rendering so the tap's
/// IOProc can pull it on its own real-time thread.
final class PitchGraph {
    static let maxFrames: AVAudioFrameCount = 4096

    let engine = AVAudioEngine()
    let format: AVAudioFormat
    private let timePitch = AVAudioUnitTimePitch()

    /// - Parameter latencyGuard: drop backlog so the delay can't creep up (off in the self-test,
    ///   which preloads seconds of input).
    init(sampleRate: Double, ring: OpaquePointer, offline: Bool = false, latencyGuard: Bool = true) throws {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let primeFrames = Int(sampleRate * 0.04)
        let maxLatencyFrames = Int(sampleRate * 0.25)
        let targetLatencyFrames = Int(sampleRate * 0.06)
        var priming = true

        let source = AVAudioSourceNode(format: format) { isSilence, _, frameCount, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let n = Int(frameCount)
            let left = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let right = buffers[1].mData!.assumingMemoryBound(to: Float.self)

            var fill = pt_ring_fill(ring)
            if latencyGuard && fill > maxLatencyFrames {
                pt_ring_skip(ring, fill - targetLatencyFrames)
                fill = targetLatencyFrames
            }
            // After an underrun, wait for a small cushion so we don't stutter frame-by-frame.
            if priming {
                guard fill >= primeFrames + n else {
                    left.update(repeating: 0, count: n)
                    right.update(repeating: 0, count: n)
                    isSilence.pointee = true
                    return noErr
                }
                priming = false
            }
            let got = pt_ring_read(ring, left, right, n)
            if got < n {
                (left + got).update(repeating: 0, count: n - got)
                (right + got).update(repeating: 0, count: n - got)
                priming = true
            }
            return noErr
        }

        engine.attach(source)
        engine.attach(timePitch)
        try engine.enableManualRenderingMode(offline ? .offline : .realtime, format: format,
                                             maximumFrameCount: Self.maxFrames)
        engine.connect(source, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    func apply(_ params: PitchParams) {
        timePitch.pitch = Float(params.totalCents)
        timePitch.bypass = params.isNeutral
    }

    func stop() {
        engine.stop()
    }
}
