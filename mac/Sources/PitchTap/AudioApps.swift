import AppKit
import CoreAudio

/// An app that has audio processes registered with Core Audio. Browsers and Electron apps play
/// audio from helper processes, so each app groups every process whose bundle ID starts with its own.
struct AudioApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let processes: [AudioObjectID]
    let isPlaying: Bool

    var id: String { bundleID }
    var source: AudioSource { .app(bundleID: bundleID, name: name) }
}

enum AudioApps {
    private static let safariBundleID = "com.apple.Safari"

    /// Apps currently known to Core Audio, playing ones first. PitchTap itself is left out.
    static func list() -> [AudioApp] {
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
        var groups: [String: (name: String, processes: [AudioObjectID], playing: Bool)] = [:]

        for process in processObjects() {
            guard let bundleID = try? CA.readString(process, kAudioProcessPropertyBundleID), !bundleID.isEmpty,
                  bundleID != Bundle.main.bundleIdentifier
            else { continue }

            let owner: NSRunningApplication?
            if bundleID.hasPrefix("com.apple.WebKit") {
                // Safari's audio comes from WebKit's shared GPU process.
                owner = regularApps.first { $0.bundleIdentifier == safariBundleID }
            } else {
                owner = regularApps
                    .filter { bundleID.hasPrefix($0.bundleIdentifier!) }
                    .max { $0.bundleIdentifier!.count < $1.bundleIdentifier!.count }
            }
            guard let owner, let ownerID = owner.bundleIdentifier else { continue }

            let playing = ((try? CA.read(process, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0) != 0
            var group = groups[ownerID] ?? (owner.localizedName ?? ownerID, [], false)
            group.processes.append(process)
            group.playing = group.playing || playing
            groups[ownerID] = group
        }

        return groups.map { AudioApp(bundleID: $0.key, name: $0.value.name, processes: $0.value.processes.sorted(),
                                     isPlaying: $0.value.playing) }
            .sorted { ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased()) }
    }

    static func processes(forBundleID bundleID: String) -> [AudioObjectID] {
        list().first { $0.bundleID == bundleID }?.processes ?? []
    }

    /// PitchTap's own Core Audio process object, which a system-wide tap must exclude so we don't
    /// capture our own output and feed it back.
    static func ownProcessObject() -> AudioObjectID? {
        var addr = CA.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    /// Whether any process other than PitchTap is outputting audio, including command-line tools.
    static func anyOtherProcessPlaying() -> Bool {
        let me = ownProcessObject()
        return processObjects().contains { process in
            process != me && ((try? CA.read(process, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0) != 0
        }
    }

    private static func processObjects() -> [AudioObjectID] {
        (try? CA.readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList,
                           of: AudioObjectID.self, initial: 0)) ?? []
    }
}
