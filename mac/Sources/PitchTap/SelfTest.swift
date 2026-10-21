import AVFoundation
import CPitchRing

/// `PitchTap --selftest`: runs a 440 Hz sine through `PitchGraph` offline and checks the output
/// pitch and how much input was consumed (i.e. tempo). Needs no audio hardware.
enum SelfTest {
    private struct Case {
        let name: String
        let params: PitchParams
        let expectedHz: Double
    }

    static func run() -> Int32 {
        let sampleRate = 48_000.0
        let inputHz = 440.0
        let cases = [
            Case(name: "pitch +0", params: PitchParams(), expectedHz: 440),
            Case(name: "pitch +12", params: PitchParams(semitones: 12), expectedHz: 880),
            Case(name: "pitch -5", params: PitchParams(semitones: -5), expectedHz: 440 * pow(2, -5.0 / 12)),
            Case(name: "pitch +3 +25c", params: PitchParams(semitones: 3, cents: 25),
                 expectedHz: 440 * pow(2, 3.25 / 12)),
            Case(name: "pitch -12 -50c", params: PitchParams(semitones: -12, cents: -50),
                 expectedHz: 440 * pow(2, -12.5 / 12)),
        ]

        var failures = 0
        for testCase in cases {
            do {
                let (hz, tempo) = try measure(testCase.params, sampleRate: sampleRate, inputHz: inputHz)
                let ok = abs(hz / testCase.expectedHz - 1) < 0.01 && abs(tempo - 1) < 0.03
                if !ok { failures += 1 }
                print(String(format: "%@  %-14@ %7.1f Hz (want %7.1f)  tempo %.3f (want 1.000)",
                             ok ? "PASS" : "FAIL", testCase.name as NSString, hz, testCase.expectedHz, tempo))
            } catch {
                failures += 1
                print("FAIL  \(testCase.name): \(error)")
            }
        }
        if let delay = try? measureDelay(sampleRate: sampleRate, inputHz: inputHz) {
            print(String(format: "Delay through the shifter: %.0f ms", delay * 1000))
        }
        print(failures == 0 ? "All \(cases.count) checks passed." : "\(failures) of \(cases.count) checks failed.")
        return failures == 0 ? 0 : 1
    }

    /// Seconds from a tone starting at the input to it being heard at the output, shifted −3 semitones.
    private static func measureDelay(sampleRate: Double, inputHz: Double) throws -> Double? {
        let inputFrames = Int(sampleRate * 2), onset = Int(sampleRate * 0.5)
        let ring = pt_ring_create(inputFrames)!
        defer { pt_ring_destroy(ring) }
        let input = (0..<inputFrames).map {
            $0 < onset ? 0 : Float(0.5 * sin(2 * .pi * inputHz * Double($0) / sampleRate))
        }
        _ = input.withUnsafeBufferPointer { pt_ring_write(ring, $0.baseAddress!, $0.baseAddress!, inputFrames, 1) }

        let graph = try PitchGraph(sampleRate: sampleRate, ring: ring, offline: true, latencyGuard: false)
        graph.apply(PitchParams(semitones: -3))
        defer { graph.stop() }
        let chunk = AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: PitchGraph.maxFrames)!
        var rendered = 0
        while rendered < inputFrames {
            guard try graph.engine.renderOffline(PitchGraph.maxFrames, to: chunk) == .success else { return nil }
            let samples = UnsafeBufferPointer(start: chunk.floatChannelData![0], count: Int(chunk.frameLength))
            if let i = samples.firstIndex(where: { abs($0) > 0.05 }) {
                return Double(rendered + i - onset) / sampleRate
            }
            rendered += Int(chunk.frameLength)
        }
        return nil
    }

    private static func measure(_ params: PitchParams, sampleRate: Double, inputHz: Double) throws
        -> (hz: Double, tempo: Double) {
        let inputFrames = Int(sampleRate * 8)
        let ring = pt_ring_create(inputFrames)!
        defer { pt_ring_destroy(ring) }
        let sine = (0..<inputFrames).map { Float(0.5 * sin(2 * .pi * inputHz * Double($0) / sampleRate)) }
        _ = sine.withUnsafeBufferPointer { pt_ring_write(ring, $0.baseAddress!, $0.baseAddress!, inputFrames, 1) }

        let graph = try PitchGraph(sampleRate: sampleRate, ring: ring, offline: true, latencyGuard: false)
        graph.apply(params)
        defer { graph.stop() }

        let outputFrames = Int(sampleRate * 3)
        let chunk = AVAudioPCMBuffer(pcmFormat: graph.format, frameCapacity: PitchGraph.maxFrames)!
        var output: [Float] = []
        output.reserveCapacity(outputFrames)
        // Tempo = input consumed per output frame, measured between 1 s and the end so the
        // fixed read-ahead (priming + DSP latency) cancels out.
        var consumedAtOneSecond: Int?
        while output.count < outputFrames {
            if consumedAtOneSecond == nil && output.count >= Int(sampleRate) {
                consumedAtOneSecond = inputFrames - pt_ring_fill(ring)
            }
            let n = min(PitchGraph.maxFrames, AVAudioFrameCount(outputFrames - output.count))
            guard try graph.engine.renderOffline(n, to: chunk) == .success else { break }
            output.append(contentsOf: UnsafeBufferPointer(start: chunk.floatChannelData![0],
                                                          count: Int(chunk.frameLength)))
        }
        let consumed = inputFrames - pt_ring_fill(ring) - (consumedAtOneSecond ?? 0)

        // Frequency from rising zero crossings, skipping the first 0.5 s (latency + settling).
        let start = Int(sampleRate * 0.5)
        var first = -1.0, last = -1.0, crossings = 0
        for i in (start + 1)..<output.count where output[i - 1] < 0 && output[i] >= 0 {
            let t = Double(i - 1) + Double(-output[i - 1] / (output[i] - output[i - 1]))
            if first < 0 { first = t } else { crossings += 1 }
            last = t
        }
        let hz = crossings > 0 ? Double(crossings) * sampleRate / (last - first) : 0
        return (hz, Double(consumed) / (Double(output.count) - sampleRate))
    }
}
