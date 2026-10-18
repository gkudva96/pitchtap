import AppKit
import CPitchRing

/// `PitchTap --probe [seconds] [logfile] [system|<bundle id>]`: taps the source for a few seconds with
/// the saved pitch and reports what happened. Run it from the .app
/// (`open -W PitchTap.app --args --probe 8 /tmp/probe.txt system`) so the System Audio Recording
/// permission is asked for PitchTap itself.
///
/// For the system source it also plays a −60 dBFS tone through PitchTap's own output. If PitchTap
/// were (wrongly) tapping itself, that tone would show up as captured frames while nothing else plays.
enum Probe {
    static func run(arguments: [String]) -> Never {
        let args = Array(arguments.dropFirst())
        let seconds = args.first.flatMap(Double.init) ?? 6
        let logPath = args.count > 1 ? args[1] : nil
        let sourceArg = args.count > 2 ? args[2] : "system"
        var lines: [String] = []
        func log(_ s: String) {
            lines.append(s)
            print(s)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let apps = AudioApps.list()
        log("Audio apps: " + apps.map { "\($0.name) [\($0.bundleID)] \($0.processes)\($0.isPlaying ? " playing" : "")" }
            .joined(separator: ", "))
        log("Own process object: \(AudioApps.ownProcessObject().map(String.init) ?? "none")")

        let source: AudioSource
        if sourceArg == "system" {
            source = .system
        } else {
            source = .app(bundleID: sourceArg, name: apps.first { $0.bundleID == sourceArg }?.name ?? sourceArg)
        }
        let anyonePlaying = AudioApps.anyOtherProcessPlaying()
        log("Source: \(source.name); other audio playing: \(anyonePlaying)")

        let engine = TapEngine()
        if source == .system { engine.probeToneAmplitude = 0.001 }
        var seen: [TapEngine.Status] = []
        engine.onStatus = { status in
            if seen.last != status { seen.append(status) }
        }
        engine.update(PitchParams.load())
        engine.setSource(source)
        engine.setEnabled(true)

        let started = Date()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let captured = engine.framesCaptured
            // A self-capture would feed the tone back on itself, so stop at the first sign of one.
            let selfCaptureSuspected = source == .system && !anyonePlaying && captured > 0
            guard selfCaptureSuspected || Date().timeIntervalSince(started) >= seconds else { return }
            log("Statuses: \(seen)")
            log("Frames captured: \(captured)")
            if source == .system && !anyonePlaying {
                log(captured == 0 ? "Self-exclusion: OK (our own probe tone was not captured)"
                    : "Self-exclusion: FAILED? captured audio while only PitchTap was playing")
            }
            engine.shutdown()
            if let logPath { try? lines.joined(separator: "\n").write(toFile: logPath, atomically: true, encoding: .utf8) }
            exit(0)
        }
        app.run()
        exit(0)
    }
}
