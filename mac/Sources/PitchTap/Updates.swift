import AppKit
import Combine
import Sparkle

/// Sparkle auto-updates: a daily check against the appcast in Info.plist (SUFeedURL), verified with
/// SUPublicEDKey. Found updates show Sparkle's standard window (notes, Install / Skip / Later).
final class Updates: ObservableObject {
    @Published private(set) var canCheck = false

    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                          userDriverDelegate: nil)
    private var observation: NSKeyValueObservation?

    init() {
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func check() {
        // A menu-bar-only app isn't frontmost, so bring it forward or the window opens behind others.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
