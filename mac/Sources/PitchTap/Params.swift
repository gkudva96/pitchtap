import Foundation

struct PitchParams: Equatable {
    var semitones: Int = 0 // -12...12
    var cents: Int = 0 // -50...50

    static let semitoneRange = -12...12
    static let centsRange = -50...50

    /// Common reference tunings as fine-tune offsets: 1200 × log2(target / source), rounded.
    static let tunings: [(name: String, cents: Int)] = [
        ("Standard (A = 440 Hz)", 0),
        ("A = 432 Hz", -32),
        ("From A = 442 Hz to 440", -8),
    ]

    var totalCents: Int { semitones * 100 + cents }
    var isNeutral: Bool { totalCents == 0 }

    private static let intervals = ["", "Half step", "Whole step", "Minor 3rd", "Major 3rd", "4th", "Tritone",
                                    "5th", "Minor 6th", "Major 6th", "Minor 7th", "Major 7th", "Octave"]

    /// The shift as any musician would say it, e.g. "Whole step down".
    var musicalDescription: String {
        if semitones == 0 { return cents == 0 ? "Original key" : "Original key, fine-tuned" }
        let interval = Self.intervals[abs(semitones)] + (semitones > 0 ? " up" : " down")
        return cents == 0 ? interval : "≈ " + interval
    }

    /// How to play along on a fretted instrument with the original chord shapes, or nil if no capo or
    /// retuning helps (no shift, a whole octave, or a fraction of a semitone).
    var fretHint: String? {
        guard cents == 0 else { return nil }
        // The capo fret that puts the original shapes in the shifted key; past the 7th, tune down instead.
        let fret = (semitones % 12 + 12) % 12
        let prefix = "Playing along on guitar, ukulele or another fretted instrument: "
        switch fret {
        case 0: return nil
        case 1...7: return prefix + "capo \(fret) with the original chord shapes."
        default: return prefix + "tune down \(12 - fret) semitone\(12 - fret == 1 ? "" : "s") and use the original chord shapes."
        }
    }
}

/// What gets pitch-shifted: one app (and its helper processes), or everything except PitchTap.
enum AudioSource: Equatable, Hashable {
    case system
    case app(bundleID: String, name: String)

    var name: String {
        switch self {
        case .system: return "All system audio"
        case let .app(_, name): return name
        }
    }
}

extension PitchParams {
    private enum Key {
        static let semitones = "semitones", cents = "cents"
    }

    static func load(from defaults: UserDefaults = .standard) -> PitchParams {
        PitchParams(semitones: defaults.integer(forKey: Key.semitones).clamped(to: semitoneRange),
                    cents: defaults.integer(forKey: Key.cents).clamped(to: centsRange))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(semitones, forKey: Key.semitones)
        defaults.set(cents, forKey: Key.cents)
    }
}

extension AudioSource {
    private enum Key {
        static let bundleID = "sourceBundleID", name = "sourceName"
    }

    /// Defaults to all system audio.
    static func load(from defaults: UserDefaults = .standard) -> AudioSource {
        guard let bundleID = defaults.string(forKey: Key.bundleID) else { return .system }
        return .app(bundleID: bundleID, name: defaults.string(forKey: Key.name) ?? bundleID)
    }

    func save(to defaults: UserDefaults = .standard) {
        switch self {
        case .system:
            defaults.removeObject(forKey: Key.bundleID)
            defaults.removeObject(forKey: Key.name)
        case let .app(bundleID, name):
            defaults.set(bundleID, forKey: Key.bundleID)
            defaults.set(name, forKey: Key.name)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
