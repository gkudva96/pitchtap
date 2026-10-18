import Foundation

struct PitchParams: Equatable {
    var semitones: Int = 0 // -12...12
    var cents: Int = 0 // -50...50

    static let semitoneRange = -12...12
    static let centsRange = -50...50

    var totalCents: Int { semitones * 100 + cents }
    var isNeutral: Bool { totalCents == 0 }
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
