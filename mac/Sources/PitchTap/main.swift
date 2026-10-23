import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Welcome.showIfFirstLaunch()
    }
}

struct PitchTapApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updates = Updates()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model, updates: updates)
        } label: {
            Image(nsImage: MenuBarIcon.image(active: model.enabled))
            if !model.menuBarLabel.isEmpty { Text(model.menuBarLabel) }
        }
        .menuBarExtraStyle(.window)
    }
}

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
} else if let i = CommandLine.arguments.firstIndex(of: "--probe") {
    Probe.run(arguments: Array(CommandLine.arguments[i...]))
} else {
    PitchTapApp.main()
}
