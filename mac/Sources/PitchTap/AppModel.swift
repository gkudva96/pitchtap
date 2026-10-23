import AppKit
import Carbon
import Combine
import ServiceManagement

final class AppModel: ObservableObject {
    private static let enabledKey = "enabled"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { hearingOriginal = false }
            engine.setEnabled(enabled)
        }
    }

    @Published var params: PitchParams {
        didSet {
            guard params != oldValue else { return }
            params.save()
            engine.update(audibleParams)
        }
    }

    /// Plays the source unshifted for A/B comparison. Unlike turning pitch shift off, the tap keeps
    /// running at the same latency, so switching is instant and doesn't jump in time. Not saved.
    @Published var hearingOriginal = false {
        didSet { engine.update(audibleParams) }
    }

    private var audibleParams: PitchParams { hearingOriginal ? PitchParams() : params }

    @Published var source: AudioSource {
        didSet {
            guard source != oldValue else { return }
            source.save()
            engine.setSource(source)
        }
    }

    @Published private(set) var status: TapEngine.Status = .off
    @Published private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginItemError: String?
    @Published private(set) var apps: [AudioApp] = []

    private let engine = TapEngine()

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        params = PitchParams.load()
        source = AudioSource.load()
        engine.onStatus = { [weak self] status in self?.status = status }
        engine.update(params)
        engine.setSource(source)
        engine.setEnabled(enabled)

        HotKeys.register(keyCode: kVK_UpArrow) { [weak self] in self?.nudge(by: 1) }
        HotKeys.register(keyCode: kVK_DownArrow) { [weak self] in self?.nudge(by: -1) }
        HotKeys.register(keyCode: kVK_ANSI_0) { [weak self] in self?.reset() }
        HotKeys.register(keyCode: kVK_ANSI_B) { [weak self] in
            guard let self, self.enabled else { return }
            self.hearingOriginal.toggle()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.engine.shutdown() }
    }

    func refreshApps() {
        apps = AudioApps.list()
    }

    func setLaunchesAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change Launch at login: \(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func reset() {
        hearingOriginal = false
        params = PitchParams()
    }

    private func nudge(by step: Int) {
        hearingOriginal = false
        params.semitones = (params.semitones + step).clamped(to: PitchParams.semitoneRange)
        if !enabled { enabled = true }
    }

    var statusText: String {
        switch status {
        case .off: return "Off — audio plays normally"
        case let .waiting(app): return "Waiting for \(app) to play audio…"
        case let .active(output): return "Shifting \(source.name) → \(output)"
        case .silent(_, heardAudio: true): return "Nothing playing from \(source.name) right now"
        case .silent(_, heardAudio: false): return "Nothing heard from \(source.name) yet. If it stays silent " +
            "while audio plays, allow PitchTap under System Settings › Privacy & Security › " +
            "Screen & System Audio Recording."
        case let .failed(message): return message
        }
    }

    /// Short text next to the menu bar icon.
    var menuBarLabel: String {
        guard enabled, !params.isNeutral else { return "" }
        if hearingOriginal { return "orig" }
        let semis = Double(params.totalCents) / 100
        return semis == semis.rounded() ? String(format: "%+d", Int(semis)) : String(format: "%+.2f", semis)
    }
}
