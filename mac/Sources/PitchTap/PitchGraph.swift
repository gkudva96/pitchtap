import AVFoundation
import CPitchRing
import CStretch

/// The DSP chain: ring buffer → Signalsmith Stretch → output, driven by manual rendering so the
/// tap's IOProc can pull it on its own real-time thread.
final class PitchGraph {
    static let maxFrames: AVAudioFrameCount = 4096

    let engine = AVAudioEngine()
    let format: AVAudioFormat
    private let stretch: OpaquePointer
    private let inLeft = UnsafeMutablePointer<Float>.allocate(capacity: Int(maxFrames))
    private let inRight = UnsafeMutablePointer<Float>.allocate(capacity: Int(maxFrames))

    /// - Parameter latencyGuard: drop backlog so the delay can't creep up (off in the self-test,
    ///   which preloads seconds of input).
    init(sampleRate: Double, ring: OpaquePointer, offline: Bool = false, latencyGuard: Bool = true) throws {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        stretch = pt_stretch_create(sampleRate)

        // The tap writes and the output reads in the same IOProc, so only a small cushion is needed.
        let primeFrames = Int(sampleRate * 0.01)
        let maxLatencyFrames = Int(sampleRate * 0.25)
        let targetLatencyFrames = Int(sampleRate * 0.03)
        var priming = true
        let (stretch, inLeft, inRight) = (stretch, inLeft, inRight)

        let source = AVAudioSourceNode(format: format) { _, _, frameCount, abl in
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
            // The shifter is still fed (with silence) so its delay stays constant.
            var got = 0
            if priming && fill >= primeFrames + n { priming = false }
            if !priming {
                got = pt_ring_read(ring, inLeft, inRight, n)
                if got < n { priming = true }
            }
            (inLeft + got).update(repeating: 0, count: n - got)
            (inRight + got).update(repeating: 0, count: n - got)
            pt_stretch_process(stretch, inLeft, inRight, left, right, Int32(n))
            return noErr
        }

        engine.attach(source)
        try engine.enableManualRenderingMode(offline ? .offline : .realtime, format: format,
                                             maximumFrameCount: Self.maxFrames)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    deinit {
        pt_stretch_destroy(stretch)
        inLeft.deallocate()
        inRight.deallocate()
    }

    func apply(_ params: PitchParams) {
        pt_stretch_set_semitones(stretch, Float(params.totalCents) / 100)
    }

    func stop() {
        engine.stop()
    }
}
